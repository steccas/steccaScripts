#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [-h] [-c country] [-s state] [-l location] [-o org] [-u unit] [-d days] [-b bits] [-k keytype] [-a altnames] domain"
    echo "Options:"
    echo "  -h          Show this help message"
    echo "  -c country  Country code (default: IT)"
    echo "  -s state    State/Province (default: Sicilia)"
    echo "  -l city     City/Location (default: Catania)"
    echo "  -o org      Organization (default: SemioDigital)"
    echo "  -u unit     Organizational Unit (default: SemioDigital IT)"
    echo "  -d days     Certificate validity in days (default: 365)"
    echo "  -b bits     Key size in bits (default: 2048)"
    echo "  -k keytype  Key type (rsa/ecdsa) (default: rsa)"
    echo "  -a altnames Comma-separated list of alternative domain names"
    echo "  -f          Force overwrite existing files"
    echo "  -w          Add www. subdomain"
    echo "  -v          Verbose output"
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
KEY_TYPE="rsa"
FORCE=false
ADD_WWW=false
VERBOSE=false
ALT_NAMES=""

# Function to log messages
log() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            [ "$VERBOSE" = true ] && echo "[$timestamp] INFO: $msg"
            ;;
        WARN)
            echo "[$timestamp] WARNING: $msg" >&2
            ;;
        ERROR)
            echo "[$timestamp] ERROR: $msg" >&2
            ;;
        *)
            echo "[$timestamp] $msg"
            ;;
    esac
}

# Parse arguments
while getopts "hc:s:l:o:u:d:b:k:a:fwv" opt; do
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
                log ERROR "Certificate validity must be a positive number"
                exit 1
            fi
            DAYS=$OPTARG
            ;;
        b)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]] || [ "$OPTARG" -lt 1024 ]; then
                log ERROR "Key size must be at least 1024 bits"
                exit 1
            fi
            BITS=$OPTARG
            ;;
        k)
            case "$OPTARG" in
                rsa|ecdsa)
                    KEY_TYPE="$OPTARG"
                    ;;
                *)
                    log ERROR "Invalid key type. Must be rsa or ecdsa"
                    exit 1
                    ;;
            esac
            ;;
        a)
            ALT_NAMES="$OPTARG"
            ;;
        f)
            FORCE=true
            ;;
        w)
            ADD_WWW=true
            ;;
        v)
            VERBOSE=true
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# Check for required arguments
if [ "$#" -ne 1 ]; then
    log ERROR "Missing domain argument"
    usage
fi

DOMAIN="$1"

# Check if OpenSSL is installed
if ! command -v openssl &> /dev/null; then
    log ERROR "OpenSSL is not installed. Please install OpenSSL to proceed."
    exit 1
fi

# Function to check if file exists
check_file() {
    local file="$1"
    if [ -f "$file" ] && [ "$FORCE" != true ]; then
        log ERROR "File $file already exists. Use -f to force overwrite."
        exit 1
    fi
}

# Check for existing files
check_file "rootCA.key"
check_file "rootCA.crt"
check_file "${DOMAIN}.key"
check_file "${DOMAIN}.crt"
check_file "${DOMAIN}.csr"

# Create config file for the certificate
create_config() {
    local config_file="$1"
    local san=""
    
    # Add www subdomain if requested
    if [ "$ADD_WWW" = true ]; then
        san="DNS:www.${DOMAIN}"
    fi
    
    # Add alternative names if provided
    if [ -n "$ALT_NAMES" ]; then
        IFS=',' read -ra ADDR <<< "$ALT_NAMES"
        for i in "${ADDR[@]}"; do
            [ -n "$san" ] && san="${san},"
            san="${san}DNS:${i}"
        done
    fi
    
    cat > "$config_file" << EOF
[req]
default_bits = $BITS
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $ORG_UNIT
CN = $DOMAIN

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
EOF
    
    # Add SAN entries if any
    if [ -n "$san" ]; then
        local count=2
        IFS=',' read -ra ADDR <<< "$san"
        for i in "${ADDR[@]}"; do
            echo "DNS.$count = ${i#DNS:}" >> "$config_file"
            ((count++))
        done
    fi
}

# Generate Root CA key and certificate
log INFO "Generating Root CA key and certificate..."
if [ "$KEY_TYPE" = "ecdsa" ]; then
    openssl ecparam -genkey -name secp384r1 -out rootCA.key
else
    openssl genrsa -out rootCA.key $BITS
fi

openssl req -x509 -new -nodes -key rootCA.key -sha256 -days $DAYS -out rootCA.crt \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$ORG_UNIT/CN=Root CA"

# Create OpenSSL config
CONFIG_FILE="${DOMAIN}.conf"
create_config "$CONFIG_FILE"

# Generate domain key
log INFO "Generating domain key..."
if [ "$KEY_TYPE" = "ecdsa" ]; then
    openssl ecparam -genkey -name secp384r1 -out "${DOMAIN}.key"
else
    openssl genrsa -out "${DOMAIN}.key" $BITS
fi

# Generate CSR
log INFO "Generating Certificate Signing Request..."
openssl req -new -key "${DOMAIN}.key" -out "${DOMAIN}.csr" -config "$CONFIG_FILE"

# Generate certificate
log INFO "Generating certificate..."
openssl x509 -req -in "${DOMAIN}.csr" -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
    -out "${DOMAIN}.crt" -days "$DAYS" -sha256 -extfile "$CONFIG_FILE" -extensions req_ext

# Verify certificate
log INFO "Verifying certificate..."
openssl verify -CAfile rootCA.crt "${DOMAIN}.crt"

# Clean up
rm -f "$CONFIG_FILE" rootCA.srl

# Display certificate information
if [ "$VERBOSE" = true ]; then
    log INFO "Certificate details:"
    openssl x509 -in "${DOMAIN}.crt" -text -noout
fi

log INFO "Certificate generation completed successfully!"
log INFO "Generated files:"
log INFO "- Root CA Key: rootCA.key"
log INFO "- Root CA Certificate: rootCA.crt"
log INFO "- Domain Key: ${DOMAIN}.key"
log INFO "- Domain Certificate: ${DOMAIN}.crt"
log INFO "- Domain CSR: ${DOMAIN}.csr"

exit 0