package main

import (
	"bytes"
	"crypto"
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/x509"
	_ "embed"
	"encoding/json"
	"encoding/pem"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math/big"
	"os"
	"sort"
	"strings"
	"time"
)

const maxXML = 1 << 20

//go:embed roots.json
var rootBundle []byte

func trusted(h Health) bool {
	var roots []string
	if json.Unmarshal(rootBundle, &roots) != nil {
		return false
	}
	pins := map[string]bool{}
	for _, p := range roots {
		b, _ := pem.Decode([]byte(p))
		if b == nil {
			continue
		}
		c, err := x509.ParseCertificate(b.Bytes)
		if err != nil {
			continue
		}
		pins[sha256Hex(c.RawSubjectPublicKeyInfo)] = true
	}
	if len(h.Roots) == 0 {
		return false
	}
	for _, p := range h.Roots {
		if !pins[p] {
			return false
		}
	}
	return true
}

type Key struct {
	Count        int      `xml:"CertificateChain>NumberOfCertificates"`
	Algorithm    string   `xml:"algorithm,attr"`
	Private      string   `xml:"PrivateKey"`
	Certificates []string `xml:"CertificateChain>Certificate"`
}

type Box struct {
	Keys []Key `xml:"Key"`
}

type Document struct {
	XMLName xml.Name `xml:"AndroidAttestation"`
	Count   int      `xml:"NumberOfKeyboxes"`
	Boxes   []Box    `xml:"Keybox"`
}

type Health struct {
	Identity    string    `json:"keybox_identity"`
	Roots       []string  `json:"root_public_key_hashes"`
	State       string    `json:"state"`
	Fingerprint string    `json:"fingerprint"`
	Serials     []string  `json:"serials"`
	Expires     time.Time `json:"expires"`
	Anchor      bool      `json:"anchor"`
	// serialsDec holds decimal serials: Google lists 64-bit serials in decimal and
	// 128-bit serials in hex, so revocation lookups must try both spellings.
	serialsDec []string
}

func serial(n *big.Int) string { return strings.TrimLeft(strings.ToLower(n.Text(16)), "0") }

func cleanPEM(s string) []byte {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	for i := range lines {
		lines[i] = strings.TrimSpace(lines[i])
	}
	return []byte(strings.Join(lines, "\n"))
}

func signer(data string) (crypto.Signer, error) {
	p, rest := pem.Decode(cleanPEM(data))
	if p == nil || len(bytes.TrimSpace(rest)) != 0 {
		return nil, errors.New("invalid private PEM")
	}
	if k, e := x509.ParsePKCS8PrivateKey(p.Bytes); e == nil {
		if s, ok := k.(crypto.Signer); ok {
			return s, nil
		}
	}
	if k, e := x509.ParseECPrivateKey(p.Bytes); e == nil {
		return k, nil
	}
	if k, e := x509.ParsePKCS1PrivateKey(p.Bytes); e == nil {
		return k, nil
	}
	return nil, errors.New("unsupported private key")
}

func inspect(data []byte, now time.Time) (Health, error) {
	h := Health{State: "invalid"}
	h.Fingerprint = sha256Hex(data)
	if len(data) == 0 || len(data) > maxXML {
		return h, errors.New("XML size")
	}
	data = bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf})
	if bytes.Contains(bytes.ToUpper(data), []byte("<!DOCTYPE")) || bytes.Contains(bytes.ToUpper(data), []byte("<!ENTITY")) {
		return h, errors.New("XML directives forbidden")
	}
	if err := validateXMLShape(data); err != nil {
		return h, err
	}
	var d Document
	dec := xml.NewDecoder(bytes.NewReader(data))
	if e := dec.Decode(&d); e != nil {
		return h, errors.New("invalid keybox XML values")
	}
	for {
		t, e := dec.Token()
		if e == io.EOF {
			break
		}
		if e != nil {
			return h, errors.New("invalid keybox XML syntax")
		}
		if _, ok := t.(xml.Comment); ok {
			continue
		}
		if c, ok := t.(xml.CharData); !ok || strings.TrimSpace(string(c)) != "" {
			return h, errors.New("trailing XML")
		}
	}
	if len(d.Boxes) != 1 || d.Count != 1 {
		return h, errors.New("expected one keybox")
	}
	if len(d.Boxes[0].Keys) < 1 || len(d.Boxes[0].Keys) > 4 {
		return h, errors.New("key count")
	}
	h.State = "valid"
	identities := []string{}
	algorithms := map[string]bool{}
	for _, k := range d.Boxes[0].Keys {
		if algorithms[k.Algorithm] {
			return h, errors.New("duplicate key algorithm")
		}
		algorithms[k.Algorithm] = true
		s, e := signer(k.Private)
		if e != nil {
			return h, e
		}
		switch s.(type) {
		case *rsa.PrivateKey:
			if k.Algorithm != "rsa" {
				return h, errors.New("algorithm label mismatch")
			}
		case *ecdsa.PrivateKey:
			if k.Algorithm != "ecdsa" {
				return h, errors.New("algorithm label mismatch")
			}
		default:
			return h, errors.New("key algorithm")
		}
		if len(k.Certificates) < 2 || len(k.Certificates) > 8 || k.Count != len(k.Certificates) {
			return h, errors.New("chain count")
		}
		var previous *x509.Certificate
		chain := []*x509.Certificate{}
		for i, text := range k.Certificates {
			p, rest := pem.Decode(cleanPEM(text))
			if p == nil || p.Type != "CERTIFICATE" || len(bytes.TrimSpace(rest)) != 0 {
				return h, errors.New("certificate PEM")
			}
			c, e := x509.ParseCertificate(p.Bytes)
			if e != nil {
				return h, e
			}
			chain = append(chain, c)
			if i == 0 {
				if !c.BasicConstraintsValid || !c.IsCA || c.KeyUsage&x509.KeyUsageCertSign == 0 {
					return h, errors.New("keybox certificate cannot sign attestations")
				}
				identities = append(identities, sha256Hex(c.Raw))
				a, _ := x509.MarshalPKIXPublicKey(s.Public())
				b, _ := x509.MarshalPKIXPublicKey(c.PublicKey)
				if !bytes.Equal(a, b) {
					return h, errors.New("private/public mismatch")
				}
			}
			if previous != nil {
				if e := previous.CheckSignatureFrom(c); e != nil {
					return h, fmt.Errorf("chain signature: %w", e)
				}
			}
			previous = c
			h.Serials = append(h.Serials, serial(c.SerialNumber))
			h.serialsDec = append(h.serialsDec, c.SerialNumber.String())

			if h.Expires.IsZero() || c.NotAfter.Before(h.Expires) {
				h.Expires = c.NotAfter
			}
			if now.Before(c.NotBefore) {
				h.State = "not_yet_valid"
			}
			if !now.Before(c.NotAfter) {
				h.State = "expired"
			}
		}
		if h.State == "valid" && now.Year() >= 2025 {
			roots := x509.NewCertPool()
			roots.AddCert(previous)
			intermediates := x509.NewCertPool()
			for _, c := range chain[1 : len(chain)-1] {
				intermediates.AddCert(c)
			}
			if _, er := chain[0].Verify(x509.VerifyOptions{Roots: roots, Intermediates: intermediates, CurrentTime: now, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}}); er != nil {
				return h, errors.New("unsupported certificate chain constraints")
			}
		}
		h.Roots = append(h.Roots, sha256Hex(previous.RawSubjectPublicKeyInfo))
		// Require a self-signed terminal certificate. Trust provenance remains separate.
		if e := previous.CheckSignature(previous.SignatureAlgorithm, previous.RawTBSCertificate, previous.Signature); e != nil {
			return h, errors.New("terminal signature")
		}
	}
	sort.Strings(identities)
	h.Identity = sha256Hex([]byte(strings.Join(identities, "|")))
	if now.Year() < 2025 {
		h.State = "time_unknown"
	}
	return h, nil
}

func (e *Engine) health() Health {
	b, err := readKey(e.target())
	if os.IsNotExist(err) {
		return Health{State: "missing"}
	}
	if err != nil { // unreadable, oversized or not a regular file: present but unusable, not "missing"
		return Health{State: "invalid"}
	}
	h, err := inspect(b, time.Now())
	if err != nil {
		h.State = "invalid"
	} else if !trusted(h) {
		h.State = "untrusted"
	} else if formatErr := checkConsumerFormat(b, strictProfile); formatErr != nil {
		h.State = "consumer_incompatible"
	}
	if e.isKnownAnchor(h.Identity) || e.isKnownAnchor(h.Fingerprint) {
		h.Anchor = true
	}
	return h
}
