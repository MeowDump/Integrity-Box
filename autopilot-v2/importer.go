package main

import (
	"context"
	"errors"
	"time"
)

// importKey installs exactly the given file (no fallback to other sources). It applies the
// same checks as an automatic candidate and the consumer contract: a required consumer must
// be present, and for the main keybox the consumer must accept the key or it is rolled back.
func (e *Engine) importKey(ctx context.Context, path string) error {
	if err := e.checkTime(ctx); err != nil {
		return err
	}
	data, err := readKey(path)
	if err != nil {
		return err
	}
	h, err := inspect(data, time.Now())
	if err != nil {
		return err
	}
	if h.State != "valid" || !trusted(h) {
		return errors.New("import certificate not valid or untrusted")
	}
	if err = checkConsumerFormat(data, strictProfile); err != nil {
		return err
	}
	if present, _ := e.consumerPresent(e.consumer()); e.requireConsumer && !present {
		return errors.New("required keybox consumer is not installed")
	}
	e.crl(ctx)
	if e.status.Revocation != "fresh" {
		return errors.New("import blocked: revocation status unknown or stale")
	}
	if e.isRevoked(h) {
		return errors.New("import revoked")
	}
	old, _ := readKey(e.target())
	previous := e.health()
	e.status.Local = previous
	e.status.Source = "manual_import"
	if err = e.install(data, sha256Hex(old), generation(e.brain), false); err != nil {
		return err
	}
	if e.slot != "" {
		return nil // extra slots are not the file the consumer is probed on
	}
	if result := e.verifyInstalled(ctx, data, h, previous, old); result != "keep" {
		return errors.New("the consumer refused the imported key (" + result + ")")
	}
	return nil
}
