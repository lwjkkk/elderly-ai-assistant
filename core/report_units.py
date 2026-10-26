"""Scale-preserving unit aliases shared by parsing and OCR verification.

L/l: https://www.bipm.org/en/-/resolution-cgpm-16-6
ASCII micro prefix: https://ucum.org/ucum
No digit-to-letter replacement or numeric rescaling is performed.
"""
import re

UNIT = re.compile(
    r'%|fL|pg|10\^(?:9|12)/L|'
    r'(?:μ?mol|mmol|μ?g|mg|ng|pg|g|μ?U|IU|mIU)/(?:L|dL|mL)|'
    r'(?:cell)?/(?:μL|L)|/HPF|/100WBC|mmHg|mm/h|L/L|'
    r'mL/min(?:/1\.73m[²2])?|mOsm/kgH?2?O?'
)


def normalize_unit(text):
    value = re.sub(r'\s+', '', text).replace('µ', 'μ')
    value = value.lstrip('↑↓←→')
    value = re.sub(r'^[*×](?=10)', '', value)
    value = value.replace('10⁹/', '10^9/').replace('10¹²/', '10^12/')
    value = re.sub(r'^u(?=mol/|g/|U/)', 'μ', value)
    value = re.sub(r'/(d|m|μ|u)?[lL](?=$|/)',
                   lambda m: '/' + ('μ' if m[1]=='u' else m[1] or '') + 'L', value)
    if value.startswith('ml/'):
        value = 'mL/' + value[3:]
    if value == 'fl':
        value = 'fL'
    return value


def valid_unit(text):
    return bool(UNIT.fullmatch(normalize_unit(text)))
