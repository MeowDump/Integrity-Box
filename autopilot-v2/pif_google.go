package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

// Tier "google": the maintainer-independent source. It asks the Android Flash Tool backend for the
// newest Canary build of ONE Pixel product (the installed one when it is a *_beta product, else
// bluejay) and builds the fingerprint from the build metadata, the way osm0sis' autopif4.sh does.
// No HTML scraping of the developer pages: the product comes from the installed file.
const (
	pifFlashPage  = "https://flash.android.com/"
	pifStationFmt = "https://content-flashstation-pa.googleapis.com/v1/builds?product=%s&key=%s"
)

var (
	pifAPIKey   = regexp.MustCompile(`AIza[0-9A-Za-z_-]{35}`)
	pifTrackVer = regexp.MustCompile(`^Canary (\d{4})(\d{2})$`)
	pifProduct  = regexp.MustCompile(`^[a-z0-9]{2,20}_beta$`)
	pifBuildID  = regexp.MustCompile(`^[0-9]{5,12}$`)
	pifRCName   = regexp.MustCompile(`^[A-Z0-9]{2,6}\.[0-9]{6}\.[0-9]{3}[A-Za-z0-9]{0,3}$`)
	// Products the contour can name without asking the user; others need an installed file of that product.
	pifKnownModels = map[string]struct{ Model, SDK string }{"bluejay_beta": {"Pixel 6a", "32"}}
)

type flashBuild struct {
	Product              string `json:"product"`
	BuildID              string `json:"buildId"`
	ReleaseCandidateName string `json:"releaseCandidateName"`
	PreviewMetadata      struct {
		ID                      string `json:"id"`
		ReleaseTrackVersionName string `json:"releaseTrackVersionName"`
		Canary                  bool   `json:"canary"`
		Active                  bool   `json:"active"`
	} `json:"previewMetadata"`
}

// newestCanary picks the newest active Canary build of product: highest track (canary-YYYYMM),
// then highest numeric build id. Non-Canary previews in the same list are ignored.
func newestCanary(body []byte, product string) (flashBuild, error) {
	var resp struct {
		Builds []flashBuild `json:"flashstationBuild"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return flashBuild{}, err
	}
	var best flashBuild
	var bestID int64 = -1
	for _, b := range resp.Builds {
		if b.Product != product || !b.PreviewMetadata.Canary || !b.PreviewMetadata.Active || !pifBuildID.MatchString(b.BuildID) || !pifRCName.MatchString(b.ReleaseCandidateName) {
			continue
		}
		m := pifTrackVer.FindStringSubmatch(b.PreviewMetadata.ReleaseTrackVersionName)
		if m == nil {
			continue
		}
		track, _ := strconv.ParseInt(m[1]+m[2], 10, 64)
		id, _ := strconv.ParseInt(b.BuildID, 10, 64)
		if key := track*1e12 + id; key > bestID {
			best, bestID = b, key
		}
	}
	if bestID < 0 {
		return flashBuild{}, errors.New("no active canary build in the answer")
	}
	return best, nil
}

// googleCandidateFrom builds the fingerprint file for a Canary build. cur supplies MODEL and the
// initial SDK level when the product is the one already installed.
func googleCandidateFrom(b flashBuild, cur pifFile) (pifFile, error) {
	if !pifProduct.MatchString(b.Product) {
		return pifFile{}, errors.New("product shape")
	}
	m := pifTrackVer.FindStringSubmatch(b.PreviewMetadata.ReleaseTrackVersionName)
	if m == nil {
		return pifFile{}, errors.New("track shape")
	}
	device := strings.TrimSuffix(b.Product, "_beta")
	model, sdk := "", ""
	if cur.Props["PRODUCT"] == b.Product && cur.Props["MODEL"] != "" {
		model, sdk = cur.Props["MODEL"], cur.Props["DEVICE_INITIAL_SDK_INT"]
	}
	if k, ok := pifKnownModels[b.Product]; ok && model == "" {
		model, sdk = k.Model, k.SDK
	}
	if model == "" {
		return pifFile{}, errors.New("no model known for " + b.Product)
	}
	props := map[string]string{
		"MANUFACTURER": "Google", "MODEL": model, "BRAND": "google", "PRODUCT": b.Product, "DEVICE": device, "RELEASE": "CANARY",
		"ID": b.ReleaseCandidateName, "INCREMENTAL": b.BuildID, "TYPE": "user", "TAGS": "release-keys",
		// The Canary track YYYYMM carries the patch of that month: 2026-11-05 for canary-202611 (matches the
		// maintainer's files for both known builds).
		"SECURITY_PATCH": m[1] + "-" + m[2] + "-05",
	}
	if sdk != "" {
		props["DEVICE_INITIAL_SDK_INT"] = sdk
	}
	props["FINGERPRINT"] = fmt.Sprintf("google/%s/%s:CANARY/%s/%s:user/release-keys", b.Product, device, b.ReleaseCandidateName, b.BuildID)
	f := pifFile{Props: props}
	if err := f.check(); err != nil {
		return pifFile{}, err
	}
	return f, nil
}

func (e *Engine) pifGoogleCandidate(ctx context.Context, cur pifFile) (pifFile, error) {
	product := "bluejay_beta"
	if p := cur.Props["PRODUCT"]; pifProduct.MatchString(p) {
		product = p
	}
	page, err := e.get(ctx, pifFlashPage, 256<<10)
	if err != nil {
		return pifFile{}, err
	}
	key := pifAPIKey.Find(page)
	if key == nil {
		return pifFile{}, errors.New("api key not found on the flash tool page")
	}
	body, err := e.getHeaders(ctx, fmt.Sprintf(pifStationFmt, url.QueryEscape(product), url.QueryEscape(string(key))), 1<<20,
		http.Header{"Referer": []string{"https://flash.android.com"}})
	if err != nil {
		return pifFile{}, err
	}
	b, err := newestCanary(body, product)
	if err != nil {
		return pifFile{}, err
	}
	return googleCandidateFrom(b, cur)
}
