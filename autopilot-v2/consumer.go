package main

import (
	"bytes"
	"encoding/pem"
	"encoding/xml"
	"errors"
	"fmt"
)

// ConsumerProfile describes which private-key PEM types a keybox consumer can load.
// A file that fits the strict profile also fits every more tolerant consumer.
type ConsumerProfile struct {
	ID         string
	AllowedPEM map[string][]string // key algorithm -> accepted PEM block types
}

// strictProfile is the intersection of known consumers. Tricky Store 1.4.1 fails with
// ClassCastException on PKCS#8 ("PRIVATE KEY") keys, so only SEC1/PKCS#1 are allowed.
var strictProfile = ConsumerProfile{ID: "strict", AllowedPEM: map[string][]string{
	"ecdsa": {"EC PRIVATE KEY"},
	"rsa":   {"RSA PRIVATE KEY"},
}}

// checkConsumerFormat verifies data against the profile without changing it.
func checkConsumerFormat(data []byte, p ConsumerProfile) error {
	var d Document
	if err := xml.Unmarshal(bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf}), &d); err != nil {
		return errors.New("consumer format: unreadable XML")
	}
	for _, box := range d.Boxes {
		for _, k := range box.Keys {
			allowed := p.AllowedPEM[k.Algorithm]
			if len(allowed) == 0 {
				return fmt.Errorf("consumer format: algorithm %q is not supported", k.Algorithm)
			}
			block, _ := pem.Decode(cleanPEM(k.Private))
			if block == nil {
				return errors.New("consumer format: private key is not PEM")
			}
			ok := false
			for _, t := range allowed {
				if t == block.Type {
					ok = true
				}
			}
			if !ok {
				return fmt.Errorf("consumer format: %s key uses PEM type %q", k.Algorithm, block.Type)
			}
		}
	}
	return nil
}
