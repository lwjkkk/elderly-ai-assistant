"""Context-aware red flags; screening signals, never a diagnosis or exhaustive list.

Sources (review with clinical testers before treating coverage as validated):
https://www.cdc.gov/heart-disease/about/heart-attack.html
https://www.cdc.gov/stroke/signs-symptoms/
https://www.nhsinform.scot/tests-and-treatments/first-aid/anaphylaxis-first-aid/
Based on C's vocabulary, with ordinary dizziness/bleeding and nonclinical contexts
kept out of unconditional emergency rules.
"""
import re
import unicodedata

LABELS = [
    ('chest_pain', re.compile(
        r'胸痛|胸闷|(?:胸(?:口|部|前区|腔)|心(?:脏|口(?:窝)?|前区)|左胸).{0,5}'
        r'(?:疼|痛|闷|压迫|压榨|发紧|发堵|憋闷|像.{0,5}石头|压着.{0,5}石头|难受|不舒服)'), '胸痛胸闷'),
    ('breath', re.compile(
        r'呼吸困难|喘(?:不[过上]气|不上来|不上)|上不来气|气(?:上不来|接不上|不够用)|'
        r'吸不上气|呼不上气|窒息|(?:喘|呼吸).{0,3}(?:厉害|急促|不行)|憋得.{0,3}(?:喘|不能呼吸)'), '呼吸困难'),
    ('consciousness', re.compile(
        r'意识(?:模糊|不清|丧失)|昏迷|叫不醒|不省人事|(?:突然)?晕倒|晕厥|晕过去|失去意识|'
        r'(?:叫|喊|拍).{0,3}(?:不应|没反应|没有反应)'), '意识不清/晕厥'),
    ('stroke', re.compile(
        r'口(?:角|眼)歪斜|嘴(?:巴|角)?歪|一侧.{0,5}(?:麻木|发麻|无力|不能动|动不了|没知觉)|'
        r'(?:半边|一边|左边|右边|一只).{0,5}(?:身子|身体|脸|手|腿|胳膊|脚|肢体).{0,6}'
        r'(?:麻木|发麻|无力|没力|抬不起|不能动|动不了|不听使唤)|'
        r'说话(?:不清|含糊|大舌头)|吐字不清|突然.{0,6}(?:说不出话|看不见|失明)|'
        r'突然.{0,8}(?:胳膊.{0,4}抬不起|走路.{0,4}(?:歪|不稳)|站不稳)'), '中风警示表现'),
    ('bleeding', re.compile(
        r'大量(?:出|流)血|大出血|(?:血|鼻血|伤口流血).{0,3}(?:止不住|流不停)|'
        r'止不住血|流血不止|呕血|吐血|咯血|咳血|便血|黑便|拉(?:鲜血|血便)'), '出血警示表现'),
    ('choking', re.compile(
        r'噎住|卡喉|(?:食物|喉咙).{0,4}(?:卡|噎)|气道.{0,4}(?:堵|梗阻)'), '噎食/气道梗阻'),
    ('severe_headache', re.compile(
        r'霹雳样头痛|爆炸性头痛|(?:头|脑袋).{0,4}(?:炸裂|要炸|剧痛|疼得受不了|痛得受不了)|'
        r'突然.{0,5}(?:剧烈|厉害).{0,4}(?:头痛|头疼)|突然.{0,4}(?:头痛|头疼).{0,4}(?:剧烈|厉害)'), '突发剧烈头痛'),
    ('severe_allergy', re.compile(
        r'(?:舌头|舌|喉(?:咙|头|部)?).{0,3}(?:肿|水肿)|严重过敏|过敏性休克'), '严重过敏警示表现'),
]
LABEL_MAP = {key: label for key, _, label in LABELS}
LABEL_MAP['emergency_other'] = '其他需立即求助的危险表现'


def normalize(text):
    text = unicodedata.normalize('NFKC', str(text or ''))
    return re.sub(r'[\s\u200b-\u200f\ufeff]', '', text)


def current_clauses(text):
    """Keep affirmative current/recent symptoms, including recent resolved red flags."""
    q = normalize(text)
    clauses = []
    # Do not split 不过 inside 喘不过气.
    for clause in re.split(r'[，,。！？!?；;\n]|但是|然而|而是|可是|但', q):
        if not clause:
            continue
        current = bool(re.search(r'现在|刚才|今天|仍然|还在|持续|越来越|又开始|再次',clause))
        if re.search(r'预防|科普|什么是|有哪些症状|如何识别|怎么识别|什么意思',clause) and not current:
            continue
        if re.search(r'以前|曾经|去年|上个月|小时候|几年前|病史',clause) and not current:
            continue
        if re.search(r'如果|假如|万一|一旦|若出现|假设',clause) and not current:
            continue
        if re.search(r'小说|电影|游戏|新闻|测试用例|正则|词表|代码|这几个字|这个词',clause) and not current:
            continue
        clauses.append(clause)
    return clauses


def affirmative(clause, match):
    before = clause[max(0,match.start()-9):match.start()]
    return not re.search(r'(?:没有|并无|不伴有|不伴|否认|不是|无)(?:明显|任何|出现|发生|了)?$',before)


def positive_text(text):
    # Remove only negated complaint spans; a negative in one clause cannot
    # suppress a different affirmative symptom in the next clause.
    out = []
    for clause in current_clauses(text):
        for _, pattern, _ in LABELS:
            matches = list(pattern.finditer(clause))
            for match in reversed(matches):
                if not affirmative(clause,match):
                    clause = clause[:match.start()]+clause[match.end():]
        out.append(clause)
    return '，'.join(out)


def fast_types(text):
    hits = []
    for clause in current_clauses(text):
        for key, pattern, _ in LABELS:
            for match in pattern.finditer(clause):
                if not affirmative(clause,match):
                    continue
                if key=='choking' and not re.search(r'说不出|不能说话|咳不出|喘|发紫|呼吸|噎住',clause):
                    continue
                if key=='severe_allergy' and not re.search(r'呼吸|喘|吞咽|咽不下|声音.{0,3}哑|突然|迅速|休克',clause):
                    continue
                if key not in hits:
                    hits.append(key)
    # A domain-independent severity net complements enumerated symptoms.
    q = positive_text(text)
    bodily = re.search(r'身体|身子|难受|不舒服|不对劲|动不了|人不行|撑不住|快不行',q)
    severe = re.search(r'救命|快不行|撑不住|快死|受不了|越来越严重|迅速加重',q)
    if bodily and severe and not hits:
        hits.append('emergency_other')
    return hits


def semantic_candidate(text):
    q = positive_text(text)
    # Routine questions do not incur a second model call. Ambiguous bodily
    # complaints are screened; no list can guarantee recognition of all speech.
    if not q or re.search(r'手机|屏幕|电脑|微信|游戏|软件',q) and not re.search(r'身体|胸|心脏|呼吸|老人|妈妈|爸爸',q):
        return False
    return bool(re.search(r'难受|不舒服|不对劲|说不上|晕|疼|痛|麻|肿|喘|不听使唤|使不上劲|'
                          r'心慌|心悸|狂跳|乱跳|越来越严重|迅速加重|看不清|吞不下|快帮|救命|'
                          r'(?:胸口|心口|心脏).{0,8}(?:像|攥|揪|扑腾|打鼓)|'
                          r'说不顺|说不利索|讲不清|天旋地转|眼前一黑|咽不下|'
                          r'(?:手|脚|胳膊|腿|嘴|舌|眼睛|眼前|身子|身体).{0,10}(?:不是自己|不受控制|不听|使不上|异常|像)|'
                          r'(?:不能|无法|不太能).{0,5}(?:站|走|呼吸|说|看|活动|吞|动)|'
                          r'(?:喉咙|气管).{0,5}(?:堵|卡|噎)|突然.{0,8}(?:发抖|没劲|走不了|说不出)',q))
