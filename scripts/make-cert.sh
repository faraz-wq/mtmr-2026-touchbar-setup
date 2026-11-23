#!/bin/bash
# Creates a self-signed "Modbar Local" code-signing certificate in your login keychain.
# Needed so macOS keeps Accessibility / Screen Recording grants across rebuilds.
set -e
if security find-identity -v -p codesigning | grep -q "Modbar Local"; then echo "Certificate already exists."; exit 0; fi
T="$(mktemp -d)"; cd "$T"
cat > ext.cnf <<'CNF'
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=Modbar Local
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config ext.cnf 2>/dev/null
# macOS needs the old PKCS12 format, so use the system LibreSSL
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out c.p12 -passout pass:modbar -name "Modbar Local"
security import c.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P modbar -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" cert.pem   # macOS asks for your password
rm -f key.pem c.p12
echo "Created 'Modbar Local'."
