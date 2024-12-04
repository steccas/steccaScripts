#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-c country] [-s state] [-l location] [-o org] [-u unit] [-d days] [-b bits] domain"
    echo "Options:"
    echo "  -h          Show this help message"
    echo "  -c country  Country code (default: IT)"
    echo "  -s state    State/Province (default: Sicilia)"
    echo "  -l city     City/Location (default: Catania)"
    echo "  -o org      Organization (default: SemioDigital)"
    echo "  -u unit     Organizational Unit (default: SemioDigital IT)"
    echo "  -d days     Certificate validity in days (default: 365)"
    echo "  -b bits     Key size in bits (default: 2048)"
    echo "  -f          Force overwrite existing files"
    echo "  -w          Add www. subdomain"
    exit 1
}

# Default values
COUNTRY="IT"
STATE="Sicilia"
CITY="Catania"
ORG="SemioDigital"
ORG_UNIT="SemioDigital IT"
DAYS=365
BITS=2048
FORCE=false
ADD_WWW=false

# Parse arguments
while getopts "hc:s:l:o:u:d:b:fw" opt; do
    case $opt in
        h)
            usage
            ;;
        c)
            COUNTRY="$OPTARG"
            ;;
        s)
            STATE="$OPTARG"
            ;;
        l)
            CITY="$OPTARG"
            ;;
        o)
            ORG="$OPTARG"
            ;;
        u)
            ORG_UNIT="$OPTARG"
            ;;
        d)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1 ]; then
                echo "Error: Days must be a positive number"
                exit 1
            fi
            DAYS="$OPTARG"
            ;;
        b)
            if ! [[ "$OPTARG" =~ ^(2048|4096|8192)$ ]]; then
                echo "Error: Bits must be 2048, 4096, or 8192"
                exit 1
            fi
            BITS="$OPTARG"
            ;;
        f)
            FORCE=true
            ;;
        w)
            ADD_WWW=true
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check for required domain argument
if [ "$#" -ne 1 ]; then
    echo "Error: Domain name argument required"
    usage
fi

DOMAIN=$1

# Check if OpenSSL is installed
if ! command -v openssl &> /dev/null; then
    echo "Error: OpenSSL is not installed"
    exit 1
fi

# Function to check if file exists
check_file() {
    if [ -f "$1" ] && [ "$FORCE" != true ]; then
        echo "Error: File $1 already exists. Use -f to force overwrite."
        exit 1
    fi
}

# Check for existing files
check_file "rootCA.key"
check_file "rootCA.crt"
check_file "${DOMAIN}.key"
check_file "${DOMAIN}.csr"
check_file "${DOMAIN}.crt"
check_file "csr.conf"
check_file "cert.conf"

echo "Generating SSL certificates for ${DOMAIN}..."
echo "Parameters:"
echo "- Country: $COUNTRY"
echo "- State: $STATE"
echo "- City: $CITY"
echo "- Organization: $ORG"
echo "- Unit: $ORG_UNIT"
echo "- Validity: $DAYS days"
echo "- Key size: $BITS bits"
echo "- WWW subdomain: $([ "$ADD_WWW" = true ] && echo "Yes" || echo "No")"
echo

# Create root CA & Private key
echo "Generating root CA and private key..."
openssl req -x509 \
    -sha256 -days "$DAYS" \
    -nodes \
    -newkey "rsa:$BITS" \
    -subj "/CN=${DOMAIN}/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/OU=${ORG_UNIT}" \
    -keyout rootCA.key -out rootCA.crt 

# Generate Private key
echo "Generating private key for ${DOMAIN}..."
openssl genrsa -out "${DOMAIN}.key" "$BITS"

# Create CSR configuration
echo "Creating CSR configuration..."
cat > csr.conf <<EOF
[ req ]
default_bits = $BITS
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $ORG_UNIT
CN = ${DOMAIN}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${DOMAIN}
$([ "$ADD_WWW" = true ] && echo "DNS.2 = www.${DOMAIN}")
EOF

# Create CSR request
echo "Creating CSR request..."
openssl req -new -key "${DOMAIN}.key" -out "${DOMAIN}.csr" -config csr.conf

# Create certificate configuration
echo "Creating certificate configuration..."
cat > cert.conf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
$([ "$ADD_WWW" = true ] && echo "DNS.2 = www.${DOMAIN}")
EOF

# Create SSL certificate
echo "Creating SSL certificate..."
openssl x509 -req \
    -in "${DOMAIN}.csr" \
    -CA rootCA.crt -CAkey rootCA.key \
    -CAcreateserial -out "${DOMAIN}.crt" \
    -days "$DAYS" \
    -sha256 -extfile cert.conf

echo
echo "SSL certificate generation completed successfully!"
echo "Generated files:"
echo "- Root CA: rootCA.key, rootCA.crt"
echo "- Domain certificate: ${DOMAIN}.key, ${DOMAIN}.csr, ${DOMAIN}.crt"
echo "- Configurations: csr.conf, cert.conf"

exit 0