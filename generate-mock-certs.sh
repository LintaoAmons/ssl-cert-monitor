#!/bin/bash
# Generate mock SSL certificates with different expiry dates for testing
# Output format: .cer (DER-encoded X.509)

CERT_DIR="${1:-$(dirname "$0")/certs}"
mkdir -p "$CERT_DIR"

echo "=== Generating mock SSL certificates ==="

# --- Helper: create expired cert using openssl ca with backdated validity ---
generate_expired_cert() {
  local out_cer="$1"
  local cn="$2"
  local days_ago_start="${3:-30}"
  local days_ago_end="${4:-5}"

  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/newcerts"

  openssl genrsa -out "$tmpdir/ca.key" 2048 2>/dev/null
  openssl req -new -x509 -key "$tmpdir/ca.key" -out "$tmpdir/ca.pem" \
    -days 3650 -subj "/CN=MockCA" 2>/dev/null

  openssl genrsa -out "$tmpdir/leaf.key" 2048 2>/dev/null
  openssl req -new -key "$tmpdir/leaf.key" -out "$tmpdir/leaf.csr" \
    -subj "/CN=${cn}/O=MockOrg" 2>/dev/null

  cat > "$tmpdir/ca.cnf" <<CACNF
[ca]
default_ca = CA_default
[CA_default]
database = $tmpdir/index.txt
new_certs_dir = $tmpdir/newcerts
serial = $tmpdir/serial
default_md = sha256
policy = policy_any
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

  openssl req -x509 -newkey rsa:2048 -keyout /dev/null -nodes \
    -out "${out_cer%.cer}.pem" \
    -days "$days" \
    -subj "/CN=${cn}/O=MockOrg" 2>/dev/null
  openssl x509 -in "${out_cer%.cer}.pem" -outform DER -out "$out_cer"
  rm -f "${out_cer%.cer}.pem"
}

# 1. Expired (5 days ago)
echo "[1/6] app-expired.cer — expired 5 days ago"
generate_expired_cert "$CERT_DIR/app-expired.cer" "app-expired.example.com" 30 5

# 2. Critical — 7 days
echo "[2/6] api-critical.cer — expires in 7 days"
generate_cert "$CERT_DIR/api-critical.cer" "api-critical.example.com" 7

# 3. Warning — 25 days
echo "[3/6] web-warning.cer — expires in 25 days"
generate_cert "$CERT_DIR/web-warning.cer" "web-warning.example.com" 25

# 4. Alert — 60 days (within 90-day alert threshold)
echo "[4/6] staging-alert.cer — expires in 60 days"
generate_cert "$CERT_DIR/staging-alert.cer" "staging.example.com" 60

# 5. OK — 180 days
echo "[5/6] backend-ok.cer — expires in 180 days"
generate_cert "$CERT_DIR/backend-ok.cer" "backend.example.com" 180

# 6. OK — 365 days
echo "[6/6] internal-ok.cer — expires in 365 days"
generate_cert "$CERT_DIR/internal-ok.cer" "internal-ok.example.com" 365

echo ""
echo "=== Generated certificates ==="
for f in "$CERT_DIR"/*.cer; do
  cn=$(openssl x509 -inform DER -in "$f" -noout -subject 2>/dev/null | sed 's/.*CN *= *//')
  enddate=$(openssl x509 -inform DER -in "$f" -noout -enddate 2>/dev/null | cut -d= -f2)
  echo "  $(basename "$f")  CN=$cn  Expires=$enddate"
done
