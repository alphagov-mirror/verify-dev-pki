#!/bin/bash
set -o errexit

# Ensure that cfssl and its related tools are on the PATH
PATH=$PATH:$GOPATH/bin/

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Directories we create
PKI_DIR="$ROOT_DIR/src/main/resources"
CA_CERTS_DIR="$PKI_DIR/ca-certificates"
DEV_KEYS_DIR="$PKI_DIR/dev-keys"

# Directories / files we use
CSR_TEMPLATE="$ROOT_DIR/scripts/template-csr.json"
CFSSL_CONFIG="$ROOT_DIR/scripts/cfssl-config.json"

# Recreate the directory structure
rm -rf $PKI_DIR && mkdir -p $CA_CERTS_DIR $DEV_KEYS_DIR

# Create the CA certs
cd $CA_CERTS_DIR

sed 's/$COMMON_NAME/GOV.UK Verify Test Root CA/' $CSR_TEMPLATE | cfssl genkey -initca /dev/stdin | cfssljson -bare verify-root-ca

function createInterCa {
	name=$1
	commonName=$2
	sed "s/\$COMMON_NAME/$commonName/" $CSR_TEMPLATE |
	cfssl gencert -config $CFSSL_CONFIG -profile intermediate -ca ./verify-root-ca.pem -ca-key ./verify-root-ca-key.pem /dev/stdin |
	cfssljson -bare $name
}
createInterCa verify-core-ca 'GOV.UK Verify Test Core CA'
createInterCa verify-intermediary-ca 'GOV.UK Verify Test Intermediate CA'
createInterCa verify-intermediary-rp-ca 'GOV.UK Verify Test Intermediate RP CA'
createInterCa verify-metadata-ca 'GOV.UK Verify Test Metadata CA'

# Add .test to all of the generated pems (to match the old file names)
for file in *.pem; do mv $file $file.test; done

# Generate leaf certs and keys
cd $DEV_KEYS_DIR

sed 's/$COMMON_NAME/Expired Test/' $CSR_TEMPLATE | cfssl selfsign -config $CFSSL_CONFIG -profile signing_expired dev.signin.service.gov.uk /dev/stdin | cfssljson -bare expired_self_signed_signing

function createLeaf {
	name=$1
	ca=$2
	profile=$3
	commonName=$4
	sed "s/\$COMMON_NAME/$commonName/" $CSR_TEMPLATE |
	cfssl gencert -config $CFSSL_CONFIG -profile $profile -ca $CA_CERTS_DIR/$ca.pem.test -ca-key $CA_CERTS_DIR/$ca-key.pem.test /dev/stdin |
	cfssljson -bare $name
}
createLeaf verify-metadata_signing_a                 		 verify-metadata-ca        signing            			'GOV.UK Verify Test Metadata Signing A'
createLeaf verify-metadata_signing_b                 		 verify-metadata-ca        signing            			'GOV.UK Verify Test Metadata Signing B'
createLeaf verify-hub_signing_primary                		 verify-core-ca           signing            			'GOV.UK Verify Test Hub Signing'
createLeaf verify-hub_encryption_primary             		 verify-core-ca           encipherment       			'GOV.UK Verify Test Hub Encryption'
createLeaf verify-hub_connector_signing_primary      		 verify-core-ca           signing            			'GOV.UK Verify Test Connector Hub Signing'
createLeaf verify-hub_connector_encryption_primary   		 verify-core-ca           encipherment       			'GOV.UK Verify Test Connector Hub Encryption'
createLeaf verify-sample_rp_encryption_primary       		 verify-intermediary-rp-ca encipherment       			'GOV.UK Verify Test Sample RP Encryption'
createLeaf verify-sample_rp_msa_encryption_primary   		 verify-intermediary-rp-ca encipherment       			'GOV.UK Verify Test Sample RP MSA Encryption'
createLeaf verify-sample_rp_msa_signing_primary      		 verify-intermediary-rp-ca signing            			'GOV.UK Verify Test Sample RP MSA Signing'
createLeaf verify-sample_rp_signing_primary          		 verify-intermediary-rp-ca signing            			'GOV.UK Verify Test Sample RP Signing'
createLeaf verify-stub_idp_signing_primary           		 verify-intermediary-ca    signing            			'GOV.UK Verify Test Stub IDP Signing'
createLeaf verify-stub_country_signing_primary       		 verify-intermediary-ca    signing            			'GOV.UK Verify Test Stub Country Signing'
createLeaf verify-hub_signing_secondary              		 verify-core-ca           signing            			'GOV.UK Verify Test Hub Signing'
createLeaf verify-hub_encryption_secondary           		 verify-core-ca           encipherment       			'GOV.UK Verify Test Hub Encryption'
createLeaf verify-sample_rp_encryption_secondary     		 verify-intermediary-rp-ca encipherment       			'GOV.UK Verify Test Sample RP Encryption'
createLeaf verify-sample_rp_msa_encryption_secondary 		 verify-intermediary-rp-ca encipherment       			'GOV.UK Verify Test Sample RP MSA Encryption'
createLeaf verify-sample_rp_msa_signing_secondary    		 verify-intermediary-rp-ca signing            			'GOV.UK Verify Test Sample RP MSA Signing'
createLeaf verify-sample_rp_signing_secondary        		 verify-intermediary-rp-ca signing            			'GOV.UK Verify Test Sample RP Signing'
createLeaf verify-stub_idp_signing_secondary         		 verify-intermediary-ca    signing            			'GOV.UK Verify Test Stub IDP Signing'
createLeaf verify-stub_country_signing_secondary     		 verify-intermediary-ca    signing            			'GOV.UK Verify Test Stub Country Signing'
createLeaf verify-stub_country_signing_tertiary      		 verify-intermediary-ca    signing_low_date   			'GOV.UK Verify Test Stub Country Signing'
createLeaf verify-stub_country_signing_expired       		 verify-intermediary-ca    signing_expired    			'GOV.UK Verify Test Stub Country Signing'
createLeaf verify-stub_country_signing_not_yet_valid      verify-intermediary-ca    signing_not_yet_valid   'GOV.UK Verify Test Stub Country Signing'
createLeaf verify-expired_signing                    		 verify-core-ca           signing_expired    			'Expired Signing Test'

# Convert all the keys to .pk8 files
for file in *-key.pem
do
  openssl pkcs8 -topk8 -inform PEM -outform DER -in $file -out ${file%-key.pem}.pk8 -nocrypt
done

# Remove the files we no longer need
rm *.csr *-key.pem

# Rename the pem files to .crt (to match old file names)
for file in *.pem; do mv $file ${file%.pem}.crt; done

# Remove the files we no longer need
cd $CA_CERTS_DIR
rm *.csr *-key.pem.test
