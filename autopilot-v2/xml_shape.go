package main

import (
	"bytes"
	"encoding/xml"
	"errors"
	"io"
	"strings"
)

type xmlFrame struct {
	name     string
	children map[string]int
	textSeen bool
}

// Reject constructs where Go's last scalar / namespace matching could disagree
// with the consumer's first-child parser. Certificate arrays remain repeatable.
func validateXMLShape(data []byte) error {
	dec := xml.NewDecoder(bytes.NewReader(data))
	stack := []xmlFrame{}
	roots := 0
	for {
		token, err := dec.Token()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return errors.New("invalid keybox XML syntax")
		}
		switch t := token.(type) {
		case xml.StartElement:
			if len(stack) >= 16 || t.Name.Space != "" {
				return errors.New("unsupported XML depth or namespace")
			}
			attrs := map[xml.Name]bool{}
			for _, a := range t.Attr {
				if (t.Name.Local == "PrivateKey" || t.Name.Local == "Certificate") && a.Name.Local == "format" && a.Value != "pem" {
					return errors.New("unsupported keybox encoding")
				}
				if attrs[a.Name] || a.Name.Space != "" {
					return errors.New("ambiguous XML attributes")
				}
				attrs[a.Name] = true
			}
			if len(stack) == 0 {
				roots++
				if roots > 1 {
					return errors.New("multiple XML roots")
				}
			} else {
				parent := &stack[len(stack)-1]
				parent.children[t.Name.Local]++
				scalar := (parent.name == "AndroidAttestation" && (t.Name.Local == "NumberOfKeyboxes" || t.Name.Local == "Keybox")) || (parent.name == "Key" && (t.Name.Local == "PrivateKey" || t.Name.Local == "CertificateChain")) || (parent.name == "CertificateChain" && t.Name.Local == "NumberOfCertificates")
				if scalar && parent.children[t.Name.Local] > 1 {
					return errors.New("duplicate XML field")
				}
				switch parent.name {
				case "PrivateKey", "Certificate", "NumberOfKeyboxes", "NumberOfCertificates":
					return errors.New("nested scalar XML field")
				}
			}
			stack = append(stack, xmlFrame{name: t.Name.Local, children: map[string]int{}})
		case xml.EndElement:
			if len(stack) == 0 {
				return errors.New("unbalanced XML")
			}
			stack = stack[:len(stack)-1]
		case xml.CharData:
			if len(stack) == 0 && strings.Trim(string(t), " \t\r\n") != "" {
				return errors.New("text outside XML root")
			}
			if len(stack) > 0 {
				frame := &stack[len(stack)-1]
				switch frame.name {
				case "PrivateKey", "Certificate", "NumberOfKeyboxes", "NumberOfCertificates":
					text := strings.Trim(string(t), " \t\r\n")
					if text != "" {
						if frame.textSeen {
							return errors.New("split scalar XML field")
						}
						frame.textSeen = true
						if frame.name == "NumberOfKeyboxes" || frame.name == "NumberOfCertificates" {
							if len(text) > 3 {
								return errors.New("keybox count out of range")
							}
							for _, c := range text {
								if c < '0' || c > '9' {
									return errors.New("invalid numeric XML field")
								}
							}
						}
					}
				}
			}
		case xml.Directive:
			return errors.New("XML directive forbidden")
		}
	}
}
