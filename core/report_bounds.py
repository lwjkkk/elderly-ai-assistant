"""Compare the set denoted by a limit result, without inventing a point value."""
from decimal import Decimal


def _decimal(value):
    return None if value is None else Decimal(str(value))


def _intersects(first, second):
    lo1, hi1, li1, ui1 = first
    lo2, hi2, li2, ui2 = second
    if lo1 is None or (lo2 is not None and lo2 > lo1):
        lo, li = lo2, li2
    elif lo2 is None or lo1 > lo2:
        lo, li = lo1, li1
    else:
        lo, li = lo1, li1 and li2
    if hi1 is None or (hi2 is not None and hi2 < hi1):
        hi, ui = hi2, ui2
    elif hi2 is None or hi1 < hi2:
        hi, ui = hi1, ui1
    else:
        hi, ui = hi1, ui1 and ui2
    return lo is None or hi is None or lo < hi or (lo == hi and li and ui)


def compare_limit(operator, value, bounds):
    if not bounds:
        return {'possible_statuses': [], 'certain': False,
                'note': '界限结果的参考条件缺失，不能判断高低'}
    lower = operator in ('>', '>=', '≥', '≧')
    inclusive = operator in ('>=', '≤', '<=', '≥', '≦', '≧')
    limit = _decimal(value)
    result = (limit, None, inclusive, False) if lower else (None, limit, False, inclusive)
    lo, hi = _decimal(bounds['lo']), _decimal(bounds['hi'])
    li, ui = bounds['lo_inclusive'], bounds['hi_inclusive']
    possible = []
    if lo is not None and _intersects(result, (None, lo, False, not li)):
        possible.append('low')
    if _intersects(result, (lo, hi, li, ui)):
        possible.append('normal')
    if hi is not None and _intersects(result, (hi, None, not ui, False)):
        possible.append('high')
    labels = {'low':'偏低', 'normal':'满足报告参考条件', 'high':'偏高'}
    certain = len(possible) == 1
    note = ('界限结果所表示的全部可能数值均'+labels[possible[0]] if certain else
            '界限结果跨越报告参考条件，无法唯一确定高低，不能当作边界数值比较')
    return {'possible_statuses': possible, 'certain': certain, 'note': note}
