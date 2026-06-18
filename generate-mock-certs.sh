#!/bin/bash
# Generate mock SSL certificates with different expiry dates for testing
# Output format: .cer (DER-encoded X.509) with SAN extensions

CERT_DIR="${1:-$(dirname "$0")/certs}"
mkdir -p "$CERT_DIR"

echo "=== Generating mock SSL certificates ==="

# --- Helper: create expired cert using openssl ca with backdated validity ---
generate_expired_cert() {
  local out_cer="$1"
  local cn="$2"
  local san="$3"
  local days_ago_start="${4:-30}"
  local days_ago_end="${5:-5}"

  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/newcerts"

  openssl genrsa -out "$tmpdir/ca.key" 2048 2>/dev/null
  openssl req -new -x509 -key "$tmpdir/ca.key" -out "$tmpdir/ca.pem" \
    -days 3650 -subj "/CN=MockCA" 2>/dev/null

  openssl genrsa -out "$tmpdir/leaf.key" 2048 2>/dev/null

  # CSR with SAN via config
  cat > "$tmpdir/req.cnf" <<REQCNF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
req_extensions = v3_req
[dn]
CN = ${cn}
O = MockOrg
[v3_req]
subjectAltName = ${san}
REQCNF

  openssl req -new -key "$tmpdir/leaf.key" -out "$tmpdir/leaf.csr" \
    -config "$tmpdir/req.cnf" 2>/dev/null

  cat > "$tmpdir/ca.cnf" <<CACNF
[ca]
default_ca = CA_default
[CA_default]
database = $tmpdir/index.txt
new_certs_dir = $tmpdir/newcerts
serial = $tmpdir/serial
default_md = sha256
policy = policy_any
copy_extensions = copy
[policy_any]
countryName = optional
organizationName = optional
commonName = supplied
CACNF
  touch "$tmpdir/index.txt"
  echo "01" > "$tmpdir/serial"

  local start_date end_date
  if date -v-1d +%Y 2>/dev/null >&2; then
    start_date=$(date -u -v-${days_ago_start}d +%Y%m%d%H%M%SZ)
    end_date=$(date -u -v-${days_ago_end}d +%Y%m%d%H%M%SZ)
  else
    start_date=$(date -u -d "-${days_ago_start} days" +%Y%m%d%H%M%SZ)
    end_date=$(date -u -d "-${days_ago_end} days" +%Y%m%d%H%M%SZ)
  fi

  openssl ca -batch -config "$tmpdir/ca.cnf" \
    -cert "$tmpdir/ca.pem" -keyfile "$tmpdir/ca.key" \
    -in "$tmpdir/leaf.csr" -out "$tmpdir/leaf.pem" \
    -startdate "$start_date" -enddate "$end_date" 2>/dev/null

  openssl x509 -in "$tmpdir/leaf.pem" -outform DER -out "$out_cer" 2>/dev/null
  rm -rf "$tmpdir"
}

generate_cert() {
  local out_cer="$1"
  local cn="$2"
  local days="$3"
  local san="$4"

  local tmpdir
  tmpdir=$(mktemp -d)

  cat > "$tmpdir/ext.cnf" <<EXTCNF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_ext
[dn]
CN = ${cn}
O = MockOrg
[v3_ext]
subjectAltName = ${san}
EXTCNF

  openssl req -x509 -newkey rsa:2048 -keyout /dev/null -nodes \
    -out "$tmpdir/cert.pem" \
    -days "$days" \
    -config "$tmpdir/ext.cnf" 2>/dev/null
  openssl x509 -in "$tmpdir/cert.pem" -outform DER -out "$out_cer"
  rm -rf "$tmpdir"
}

# Helper to read SAN from cert
read_san() {
  openssl x509 -inform DER -in "$1" -noout -text 2>/dev/null \
    | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^ *//'
}

# 1. Expired (5 days ago) — single domain
echo "[1/6] app-expired.cer — expired 5 days ago"
generate_expired_cert "$CERT_DIR/app-expired.cer" \
  "app-expired.example.com" \
  "DNS:app-expired.example.com" 30 5

# 2. Critical — 7 days, wildcard + specific
echo "[2/6] api-critical.cer — expires in 7 days"
generate_cert "$CERT_DIR/api-critical.cer" \
  "api.example.com" 7 \
  "DNS:api.example.com,DNS:*.api.example.com"

# 3. Warning — 25 days, multiple SANs
echo "[3/6] web-warning.cer — expires in 25 days"
generate_cert "$CERT_DIR/web-warning.cer" \
  "web.example.com" 25 \
  "DNS:web.example.com,DNS:www.example.com,DNS:cdn.example.com"

# 4. Alert — 60 days (within 90-day alert threshold)
echo "[4/6] staging-alert.cer — expires in 60 days"
generate_cert "$CERT_DIR/staging-alert.cer" \
  "staging.example.com" 60 \
  "DNS:staging.example.com,DNS:staging-api.example.com"

# 5. OK — 180 days
echo "[5/6] backend-ok.cer — expires in 180 days"
generate_cert "$CERT_DIR/backend-ok.cer" \
  "backend.example.com" 180 \
  "DNS:backend.example.com,DNS:backend-internal.example.com"

# 6. OK — 365 days, IP SAN
echo "[6/6] internal-ok.cer — expires in 365 days"
generate_cert "$CERT_DIR/internal-ok.cer" \
  "internal.example.com" 365 \
  "DNS:internal.example.com,IP:10.0.0.1"

echo ""
echo "=== Generated certificates ==="
for f in "$CERT_DIR"/*.cer; do
  san=$(read_san "$f")
  enddate=$(openssl x509 -inform DER -in "$f" -noout -enddate 2>/dev/null | cut -d= -f2)
  echo "  $(basename "$f")  SAN=[$san]  Expires=$enddate"
done
