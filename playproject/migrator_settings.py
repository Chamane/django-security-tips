from .settings import *

DATABASES['default']['USER'] = 'djangomigrator'

with open(BASE_DIR + '/_etc_passwords_djangomigrator.txt') as fp:
    DATABASES['default']['PASSWORD'] = fp.read().strip()
