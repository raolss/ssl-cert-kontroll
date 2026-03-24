
#!/usr/bin/env bash

HOST="minasidor.nationsgardarna.se"
PORT=443

expiry=$(echo |
  openssl s_client -servername $HOST -connect $HOST:$PORT 2>/dev/null |
  openssl x509 -noout -enddate |
  sed 's/notAfter=//')

echo "Cert för $HOST går ut: $expiry"
