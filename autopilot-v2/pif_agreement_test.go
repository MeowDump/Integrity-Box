package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The engine (pif.go) and the shell doctor (doctor.sh, awk) parse the same two files
// independently. A review found three disagreements; this test keeps them from drifting again by
// running one corpus through both and demanding the same verdict.

func doctorLines(t *testing.T, pif, patch string) map[string]string {
	t.Helper()
	dir := t.TempDir()
	pp, tp := filepath.Join(dir, "custom.pif.prop"), filepath.Join(dir, "security_patch.txt")
	if err := os.WriteFile(pp, []byte(pif), 0644); err != nil {
		t.Fatal(err)
	}
	if patch != "\x00absent" {
		if err := os.WriteFile(tp, []byte(patch), 0644); err != nil {
			t.Fatal(err)
		}
	}
	cmd := exec.Command("sh", "../webroot/common_scripts/doctor.sh")
	cmd.Env = append(os.Environ(), "AP_PIF="+pp, "AP_PATCH="+tp, "AP_TODAY=2026-11-16", "AP_KEYBOX="+filepath.Join(dir, "none", "keybox.xml"),
		"AP_MODULES="+filepath.Join(dir, "nomodules"), "AP_LOGCAT="+filepath.Join(dir, "nologcat"), "AP_CONF="+filepath.Join(dir, "noconf"), "AP_NO_PROBE=1",
		"AP_BRAIN="+filepath.Join(dir, "nobrain"), "AP_ENGINE="+filepath.Join(dir, "noengine")) // never read the phone's own Custom-Patch or run a real engine
	out, _ := cmd.CombinedOutput() // the exit code reflects unrelated checks (no keybox here)
	res := map[string]string{}
	for _, l := range strings.Split(string(out), "\n") {
		f := strings.Fields(l)
		if len(f) >= 2 && (f[1] == "pif-format" || f[1] == "patch-pair") {
			res[f[1]] = f[0] + " " + strings.Join(f[2:], " ")
		}
	}
	return res
}

func TestDoctorAgreesWithTheEngineOnTheFingerprintFile(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("no sh")
	}
	base := novemberMeow
	mod := func(old, new string) string { return strings.Replace(base, old, new, 1) }
	corpus := map[string]string{
		"valid":                     base,
		"valid with configuration":  base + "\n# Configuration\nspoofBuild=1\nmodel=lowercase key after config is not ours\n",
		"crlf":                      strings.ReplaceAll(base, "\n", "\r\n"),
		"leading whitespace":        "  " + strings.ReplaceAll(base, "\n", "\n  "),
		"space before equals":       mod("MODEL=", "MODEL ="),
		"space after equals":        mod("MODEL=", "MODEL= "),
		"empty value":               mod("MODEL=Pixel 6a", "MODEL="),
		"missing key":               mod("MODEL=Pixel 6a\n", ""),
		"lowercase key":             base + "model=x\n",
		"duplicate key":             base + "MODEL=Other\n",
		"fingerprint case only":     mod("PRODUCT=bluejay_beta", "PRODUCT=BlueJay_Beta"),
		"brand case":                mod("BRAND=google", "BRAND=Google"),
		"device case":               mod("DEVICE=bluejay", "DEVICE=Bluejay"),
		"id mismatch":               mod("\nID=ZP11.261016.008", "\nID=ZP11.260918.007"),
		"tags mismatch":             mod("TAGS=release-keys", "TAGS=test-keys"),
		"space in id (both sides)":  strings.NewReplacer("ID=ZP11.261016.008", "ID=ZP11.261016 008", "/ZP11.261016.008/", "/ZP11.261016 008/").Replace(base),
		"shell metacharacters":      mod("MODEL=Pixel 6a", "MODEL=Pixel $(id)"),
		"quote in value":            mod("MODEL=Pixel 6a", `MODEL=Pixel "6a"`),
		"patch wrong shape":         mod("SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2026-11"),
		"patch impossible day":      mod("SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2026-02-30"),
		"patch leap day ok":         mod("SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2028-02-29"),
		"patch non-leap feb 29":     mod("SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2027-02-29"),
		"patch month 13":            mod("SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2026-13-01"),
		"patch year 2019":           mod("SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2019-11-05"),
		"patch year 2101":           mod("SECURITY_PATCH=2026-11-05", "SECURITY_PATCH=2101-01-01"),
		"fingerprint shape":         mod("FINGERPRINT=google/bluejay_beta/bluejay:CANARY/ZP11.261016.008/16754936:user/release-keys", "FINGERPRINT=google/bluejay"),
		"expiry comment with junk":  base + "\n# Estimated Expiry: 2026-12-01 soon\n",
		"expiry comment indented":   base + "\n   # Estimated Expiry: 2026-12-01\n",
		"no trailing newline":       strings.TrimRight(base, "\n"),
		"blank and comment lines":   "# header\n\n" + base,
		"key with digits is a typo": base + "MODEL2=x\n",
	}
	for name, text := range corpus {
		_, goErr := parsePIF([]byte(text))
		got := doctorLines(t, text, "all=2026-11-05\n")["pif-format"]
		goOK := goErr == nil
		shOK := strings.HasPrefix(got, "OK")
		if goOK != shOK {
			t.Errorf("%s: engine ok=%v (%v), doctor says %q", name, goOK, goErr, got)
		}
	}
}

func TestDoctorAgreesWithTheEngineOnTheSecurityPatchFile(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("no sh")
	}
	corpus := map[string]string{
		"all":                       "all=2026-11-05\n",
		"all other date":            "all=2026-10-05\n",
		"all compact":               "all=20261105\n",
		"all compact other":         "all=20261005\n",
		"all with spaces":           "all = 2026-11-05\n",
		"all with tabs and cr":      "all\t=\t2026-11-05\r\n",
		"bare date":                 "2026-11-05\n",
		"bare compact":              "20261105\n",
		"system month ok":           "system=202611\n",
		"system month other":        "system=202610\n",
		"system prop":               "system=prop\n",
		"all prop":                  "all=prop\n",
		"stock then month":          "system=prop\nsystem=202611\n",
		"month then stock":          "system=202611\nsystem=prop\n",
		"all beats bare date":       "2026-10-05\nall=2026-11-05\n",
		"bare date beats system":    "system=202610\n2026-11-05\n",
		"system beats stock":        "all=prop\nsystem=202611\n",
		"last all wins":             "all=2026-10-05\nall=2026-11-05\n",
		"last all wins (other)":     "all=2026-11-05\nall=2026-10-05\n",
		"comment only":              "# nothing\n",
		"garbage":                   "all=garbage\n",
		"boot key only":             "boot=2026-11-05\n",
		"boot plus all":             "boot=2026-01-01\nall=2026-11-05\n",
		"empty":                     "",
		"absent":                    "\x00absent",
		"system bad length":         "system=2026110\n",
		"all prop plus real all":    "all=prop\nall=2026-11-05\n",
		"bare date with spaces":     "  2026-11-05  \n",
		"unknown key with a date":   "vendor=2026-11-05\n",
		"all=0000":                  "all=0000-00-00\n",
		"comment after valid value": "all=2026-11-05\n# all=2026-10-05\n",
	}
	toState := func(pair string, kind string) string { // the doctor's wording -> engine's pair names
		switch {
		case strings.HasPrefix(pair, "OK") && strings.Contains(pair, "stock patch mode"):
			return "stock"
		case strings.HasPrefix(pair, "OK"):
			return "match"
		case strings.HasPrefix(pair, "FAIL"):
			return "mismatch"
		case strings.Contains(pair, "missing"):
			return "missing"
		case strings.Contains(pair, "no recognizable"):
			return "unknown"
		}
		return "?" + pair + kind
	}
	for name, text := range corpus {
		var b []byte
		if text != "\x00absent" {
			b = []byte(text)
		}
		want := parsePatchFile(b).pair("2026-11-05")
		got := toState(doctorLines(t, novemberMeow, text)["patch-pair"], "")
		if want != got {
			t.Errorf("%s (%q): engine %s, doctor %s", name, text, want, got)
		}
	}
}
