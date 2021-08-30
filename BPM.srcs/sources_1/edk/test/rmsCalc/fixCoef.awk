# Coefficients 18 bit shifted up by by 4 bits
/^ *[0-9-]/ { printf("%x\n",  $1 * 0x200000) }
