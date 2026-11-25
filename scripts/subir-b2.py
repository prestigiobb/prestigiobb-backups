import os
import sys
from datetime import datetime, timezone

import boto3

carpeta = sys.argv[1]
archivos = sorted(f for f in os.listdir(carpeta) if f.endswith('.gpg'))
if not archivos:
    raise SystemExit('No hay archivos cifrados para subir')

s3 = boto3.client(
    's3',
    endpoint_url=f"https://{os.environ['B2_ENDPOINT']}",
    aws_access_key_id=os.environ['B2_KEY_ID'],
    aws_secret_access_key=os.environ['B2_APP_KEY'],
    region_name='us-east-1',
)
fecha = datetime.now(timezone.utc).strftime('%Y-%m-%d')
for nombre in archivos:
    s3.upload_file(os.path.join(carpeta, nombre), os.environ['B2_BUCKET_NAME'], f'{fecha}/{nombre}')
print(f'Backup {fecha} subido: {len(archivos)} archivos')
