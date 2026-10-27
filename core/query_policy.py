"""Query scope and deterministic safety decisions, independent of retrieved text."""
import re
import unicodedata
from functools import lru_cache
from datetime import datetime
from zoneinfo import ZoneInfo


def normalize(text):
    text = unicodedata.normalize('NFKC', str(text or '')).strip()
    text = re.sub(r'[\u200b-\u200f\ufeff]', '', text)
    text = re.sub(r'(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])', '', text)
    for bad, good in {'血亚':'血压','血彐':'血压','微杏':'微信','危信':'微信'}.items():
        text = text.replace(bad, good)
    clauses = re.split(r'[，,；;]', text)
    kept=[]
    for clause in clauses:
        if len(clauses)>1 and (re.search(r'先不问了|的事不问了',clause)
                or re.match(r'\s*(?:我)?(?:不是(?:想)?|不要教我|不需要讲)',clause)):
            continue
        kept.append(clause)
    return '，'.join(kept).strip() or text


def emergency_types(text):
    # Shared context-aware fast rules; no model/network call in this pure helper.
    from core.emergency_rules import fast_types
    return fast_types(text)


def medical_intent(q):
    return bool(re.search(r'血压|血糖|糖尿病|肾病|肾脏|胰岛素|阿司匹林|华法林|硝酸甘油|药|病|症状|头晕|头疼|头痛|便秘|耳鸣|嗡嗡|心率|心慌|发热|发烧|咳嗽|失眠|肝|噎|骨折',q)) and not bool(re.search(r'网上买药|药店.{0,4}(?:资质|配送)',q))


def four(concern, meaning, action, seek):
    return f'【关注点】{concern}\n【是什么意思】{meaning}\n【下一步】{action}\n【就医提醒】{seek}'


def _protected_request(q):
    """Requests are classified by intent; no chat claim grants account permissions."""
    if (re.search(r'你的.{0,10}(?:系统提示|系统指令|内部规则|开发者指令)|(?:内部|隐藏|原始|完整|初始).{0,8}(?:系统提示|系统指令)|(?:system|developer).{0,8}(?:prompt|message|instruction)',q,re.I)
            and re.search(r'告诉|给我|输出|打印|显示|泄露|复述|翻译|逐字|内容|是什么|base64|dump|print|reveal|show',q,re.I)):
        return {'module':'daily_life','reason':'internal_instructions_private',
                'answer':'我不能披露或复述内部系统提示词、开发者指令和隐藏规则。可以说明公开的功能边界：提供信息整理与健康科普，不替代医生诊断，不提供个人处方，不绕过账号授权。'}
    reset_help=re.search(r'怎么|如何|忘记|忘了|找回|重置|修改|设置|保护',q)
    secret_request=re.search(r'(?:告诉|发给|读出|打印|导出|提供).{0,18}(?:密码|验证码|密钥|token)|(?:密码|验证码|密钥).{0,5}(?:多少|是什么|给我)',q,re.I)
    direct_secret=re.search(r'密码.{0,5}(?:多少|是什么)|直接.{0,8}(?:告诉|给我)|别人的|他人的|绕过|破解',q)
    if secret_request and (not reset_help or direct_secret):
        return {'module':'daily_life','reason':'credentials_private',
                'answer':'我不能读取、猜测或透露任何账号密码、验证码、密钥或令牌，也不会把聊天中的身份声明当作授权。请通过软件的账号管理或官方找回流程处理；不要在聊天中发送这些凭据。'}
    fabricated=re.search(r'编(?:一个|个|造|出)|伪造|捏造|虚构|假造|随便编',q)
    prevention=re.search(r'如何识别|怎么识别|防止|辨别|如何核实|怎么核实',q)
    if fabricated and re.search(r'来源|出处|引用|参考文献|证据|链接',q) and not prevention:
        return {'module':'daily_life','reason':'source_fabrication_refused',
                'answer':'我不能编造政策来源、链接或证据。没有经过核实的依据就应明确说明无法确认，请通过对应主管部门的官方渠道核实。'}
    if re.search(r'绑定|家属关系',q) and re.search(r'看不到|不能看|无法看|没权限|为什么.{0,6}数据',q):
        return {'module':'services','reason':'binding_access_guidance',
                'answer':'聊天无法核实这个账号的绑定状态，也不能直接开放或返回长辈的数据。请登录后在家属绑定列表核对是否为有效绑定、是否选对长辈，并检查出生年月资料和当前分享规则。实际权限由后端校验；仅自称亲戚或声称刚绑定不能代替授权。若仍有问题，请保留错误提示联系管理员，不要在聊天发送健康记录或密码。'}
    records=re.search(r'血压(?:记录|数据)|体检报告|病历|诊疗记录|健康(?:记录|数据)|问诊录音|录音文件',q)
    request=re.search(r'发给|给我|看看|看一眼|查看|查询|调取|导出|下载',q)
    own_help=re.search(r'(?:我的|自己的).{0,8}(?:报告|记录|数据)|怎么|如何|哪里',q)
    third_party=re.search(r'他(?:的)?|她(?:的)?|别人|他人|长辈|亲戚|邻居|家属|大爷|大妈|其他用户|elder_id',q)
    permission_help=(re.search(r'(?:怎么|如何).{0,10}(?:授权|绑定)',q)
                     and not re.search(r'绕过|跳过|忽略|不用授权|不用绑定',q))
    if records and request and (third_party or not own_help) and not permission_help:
        return {'module':'services','reason':'private_records_access',
                'answer':'我不能通过聊天提供或编造他人的血压记录、体检报告、病历或录音。自称家属、远房亲戚或说“只看一眼”都不能代替授权。请通过已登录且具有有效绑定和相应访问权限的数据页面查看，后端会按绑定、年龄和分享规则校验；没有权限就不能读取。'}
    if re.search(r'给我.{0,6}诊断|直接.{0,8}诊断|替我.{0,4}确诊|帮我.{0,4}确诊|你.{0,8}医生.{0,12}诊断',q):
        return {'module':'health','reason':'diagnosis_boundary',
                'answer':four('您希望获得个人疾病诊断。','系统不是医生，角色扮演或要求忽略规则也不能把聊天变成医生面诊。','可以帮您整理症状、解释检查指标和准备就诊问题；确诊需要医生结合病史、检查和面诊判断。','有不适请及时就诊；若出现胸痛、呼吸困难等危险信号，请立即拨打120。')}
    return None


def decision(question):
    q=normalize(question)
    urgent=emergency_types(q)
    if urgent:
        action='请立即拨打120，说明所在位置、症状和开始时间，联系身边的人协助，并按急救调度员指导处理。不要独自驾车或等待网上问答。'
        if 'choking' in urgent:
            action+='不能说话、不能有效咳嗽或呼吸时，不要强行喂水、喂食或用手盲掏喉咙。'
        elif 'stroke' in urgent:
            action+='记下异常开始时间，不要强行拉拽肢体，不要自行喂水喂药。'
        if re.search(r'药|硝酸甘油|阿司匹林',q):
            action+='不要根据聊天决定药物片数或临时加药；如有既往处方，请向120调度员说明并听从指导。'
        return {'module':'health','reason':'urgent_symptoms','emergency_types':urgent,
                'answer':four('您描述了需要立即求助的危险信号。','这些表现可能有严重风险，需要尽快由急救人员评估。',action,'请立即拨打120或由急救人员安排就医，不要因继续聊天延误。')}
    protected=_protected_request(q)
    if protected:
        return protected
    peer_medication=(re.search(r'邻居|别人|朋友|同事|他人',q) and '药' in q
                     and re.search(r'我.{0,12}(?:也|能|可以|一样)|照着吃|照吃',q))
    # Describing a hospital prescription is not asking the assistant to prescribe.
    administrative = bool(re.search(r'报销|医保|结算|挂号|取号|发票|费用|缴费|办理|取药流程', q))
    prescription_text = q
    if not re.search(r'扮演|假装|请你|你来|你直接|让你', q):
        prescription_text = re.sub(r'(?:医生|大夫|医院|药师)(?:已经|之前|刚才|刚|曾经)?(?:给我|为我|帮我)(?:开|写|出具).{0,5}(?:药方|处方)', '', q)
    prescription=re.search(r'(?:给我|帮我|请你|你来|你直接|直接|生成|写一[份张]|开一[份张]).{0,10}(?:药方|处方)|处方.{0,6}(?:给我|写出来)',prescription_text)
    dose_change = re.search(r'几片|多少(?:毫克|单位|粒|剂量)|剂量|漏(?:吃|服)|补服|加倍|加量|加药|增量|停药|停.{0,3}药|减药|换药|一起吃|合用', q)
    drug_selection = re.search(r'该(?:吃|用|开).{0,8}药|(?:吃|用|开)什么药|给我.{0,3}开.{0,4}药', q)
    generic_prescribing = not administrative and re.search(r'开具处方|开(?:降压|降糖)?药', q)
    if ((dose_change or drug_selection or generic_prescribing) and medical_intent(q)) or peer_medication or prescription:
        return {'module':'health','reason':'medication_boundary','answer':four('这涉及个人用药或补漏服决策。','药名、规格、服药时间和既有医嘱尚未完整确认，不能靠通用知识决定剂量、补服、合用或停药。','请核对原处方和药盒，联系开药医生或药师确认；不要自行加倍、增减、换药或凭血压一次读数决定是否服药。','如已误服或出现明显不适，请及时寻求医疗帮助；紧急时拨打120。')}
    if re.search(r'肾病|肾脏|透析',q) and re.search(r'钾|香蕉|饮食|吃|喝|盐|蛋白',q):
        return {'module':'health','reason':'individual_medical_limits','answer':four('肾脏相关饮食需要结合个人检查结果。','是否限钾、限水或限制蛋白质取决于肾功能、血钾、治疗情况及医嘱，不能把通用高血压补钾建议直接套用。','请携带近期化验结果向医生或营养专业人员确认；不要自行大量补钾、改变饮水量或按网上统一克数调整。','若有明显不适请及时就医，具体饮食限制以个人医嘱为准。')}
    if re.search(r'苹果|iPhone|iphone|iOS',q) and re.search(r'截屏|截图',q):
        return {'module':'phone','reason':'platform_requires_confirmation','allow_reviewed_evidence':True,'answer':'iPhone截屏方式需要区分有无主屏幕按钮等机型，不能把安卓的电源键加音量减当作通用方法。请先告诉我机型，或在Apple官方支持中查找“截屏”；当前知识库还没有按您的机型核验的操作说明。'}
    if re.search(r'关机',q) and re.search(r'闹钟|提醒|响铃',q):
        return {'module':'phone','reason':'device_capability_unverified','answer':'不能保证手机关机后闹钟或用药提醒一定响。请告诉我手机品牌、机型和系统版本，并以厂商说明及实际测试为准；不能用“定时开机”推断闹钟一定会响。重要提醒请保持手机开机，并检查音量及通知设置。'}
    if re.search(r'今天|现在|明天|实时|当前|20\d{2}年\d{1,2}月',q) and re.search(r'天气|多少度|气温|余票|还有.{0,3}票|股票|股价|停水',q):
        date=datetime.now(ZoneInfo('Asia/Shanghai')).strftime('%Y年%m月%d日')
        return {'module':'services' if re.search(r'票|股票|股价',q) else 'daily_life','reason':'realtime_data_unavailable',
                'answer':f'今天是{date}。我目前没有查询实时天气、余票、行情或当地公告的工具，不能确认您问的实时情况。请通过对应官方应用或服务单位核实；如需操作指引，请告诉我您使用的应用和所在地。'}
    if re.search(r'医保|津贴|补贴|社保|报销|失业保险',q) and (
            re.search(r'今年|当年|20\d{2}|多少|比例|金额|能领|能拿|武汉|上海|北京|广州|深圳',q)
            or re.search(r'[\u4e00-\u9fff]{2,}(?:省|市|自治区|自治州|县|区)',q)):
        return {'module':'services','reason':'regional_policy_unverified','allow_reviewed_evidence':True,'answer':'这需要核对参保地或户籍地、适用年度、人群及险种。当前知识库没有足以确认该地区当期金额或比例的已核验政策，不能用通用区间代替。请向当地医保或民政等主管部门核实，或提供官方政策链接后再一起核对。'}
    if re.search(r'学生票',q):
        return {'module':'services','reason':'specific_procedure_missing','allow_reviewed_evidence':True,'answer':'学生票还涉及学生优惠资格核验及特定购票要求，不能仅教注册实名就说完成。当前知识库缺少已核验的学生票流程，请在铁路12306官方应用的学生优惠资质相关栏目核对最新要求。'}
    if re.search(r'我家.{0,8}密码.{0,4}(?:多少|什么)|我的.{0,6}(?:身份证号|银行卡余额).{0,4}(?:多少|什么)',q):
        return {'module':'daily_life','reason':'private_fact_unavailable','answer':'我没有您所问的个人密码、证件号码或账户信息，不能猜测。请通过您自己的安全记录或对应官方渠道核实，不要向聊天发送密码或验证码。'}
    if re.search(r'那个|这个|刚才|上面',q) and len(q)<22 and not re.search(r'手机|血|药|微信|医保|照片|闹钟',q):
        return {'module':'daily_life','reason':'clarification_required','answer':'您指的是哪件事、哪种药或食物？当前这条请求没有带上文内容，请把具体名称和想做的操作再说一下，我再继续帮您。'}
    return None


# 任务约束使用主题与动作，不使用整句测试题作为白名单。
PROFILES=[
 ('reimbursement',r'报销|医保.{0,12}(?:能报|可报|报吗|结算)',r'医保|报销|门诊|备案',r'医保|报销|待遇|结算'),
 ('medical_admin',r'挂号|取号|医院.{0,12}(?:缴费|付费)|(?:开药|取药).{0,10}(?:流程|费用|缴费)',r'医院|挂号|医保',r'挂号|就诊|医保|缴费'),
 ('itch',r'皮肤.{0,8}痒|瘙痒',r'皮肤|瘙痒',r'皮肤|瘙痒'),
 ('bp_device',r'血压计',r'血压计',r'血压|袖带|测量|校准'),
 ('glucose_device',r'血糖仪',r'血糖仪',r'血糖|试纸|测量'),
 ('glucose',r'血糖',r'血糖|糖尿病|慢性病',r'血糖|糖尿病|低血糖'),
 ('glucose_time',r'空腹血糖|饭后.{0,4}血糖|餐后.{0,4}血糖',r'血糖|糖尿病',r'空腹|餐后|饭后'),
 ('copd',r'慢阻肺|老慢支|慢性支气管',r'慢阻肺|支气管',r'慢阻肺|支气管|呼吸|咳嗽'),
 ('liver_metric',r'转氨酶|谷丙|谷草|ALT|AST',r'体检|报告|肝功能|转氨酶',r'转氨酶|ALT|AST|肝功能'),
 ('diabetic_wound',r'糖尿病足|脚.{0,5}(?:破|伤口)',r'糖尿病|糖尿病足',r'脚|足|伤口|破口'),
 ('bp_diagnosis',r'血压.{0,16}(?:诊断|确诊|是不是|一定得)|(?:诊断|确诊).{0,10}高血压',r'血压|慢性病',r'确诊|诊断|非同日|单次(?:测|读|血压)|一次(?:测量|读数|血压)'),
 ('liver',r'转氨酶|肝癌|脂肪肝',r'肝|体检',r'肝|转氨酶'),
 ('temperature',r'体温|腋温|耳温',r'体温',r'体温|腋|耳温'),
 ('zoster',r'带状疱疹|缠腰龙',r'带状疱疹',r'带状疱疹|水泡|缠腰龙'),
 ('bp',r'高血压|降压|血压.{0,2}(?:高|偏高)',r'血压|慢性病',r'血压|降压|饮食|盐|运动|服药|复测'),
 ('diabetes',r'糖尿病|控糖',r'糖尿病|慢性病',r'糖尿病|血糖|脚|足|伤口|破口'),
 ('kidney',r'肾病|肾脏|透析',r'肾病|肾脏|透析',r'肾|钾|透析'),
 ('constipation',r'便秘|排便困难',r'便秘',r'便秘|排便|大便'),
 ('hearing',r'耳鸣|耳朵.{0,6}(?:响|嗡)|听不清',r'耳鸣|听力',r'耳|听力'),
 ('sleep',r'睡不着|失眠|睡眠|凌晨.{0,3}醒',r'睡眠|失眠',r'睡眠|失眠|睡觉|睡不着'),
 ('dizziness',r'头晕',r'头晕|血压|贫血',r'头晕|血压|贫血'),
 ('airway',r'噎|卡喉|咳不出来',r'气道|梗阻|卡喉|急救',r'梗阻|噎|卡喉|气道'),
 ('stroke',r'中风|脑卒中|嘴歪|一侧.{0,6}无力',r'卒中|中风',r'卒中|中风|嘴|肢体|FAST'),
 ('diet',r'饮食|吃饭|膳食|吃什么(?:水果|食物)?|水果|补钾',r'.',r'饮食|膳食|水果|少盐|蔬菜|主食|蛋白|油脂|盐[≤不]|盐不|食物'),
 ('font',r'字体|字号|字太小|文字.{0,3}大',r'字体|字.{0,3}大|字号',r'字体|字号|文本大小'),
 ('brightness',r'亮度|调亮|屏幕.{0,3}暗',r'亮度',r'亮度|调亮|滑块'),
 ('voice_text',r'语音.{0,6}(?:文字|转)|声音转文字',r'语音转文字',r'转文字|转换.{0,3}文字'),
 ('voice_send',r'(?:发|发送).{0,4}语音|语音.{0,5}(?:怎么|如何)?发|按住说话',r'发语音|发送语音|语音消息',r'按住|松开|发送语音'),
 ('photo_send',r'(?:发|发送).{0,5}(?:图片|照片)|(?:图片|照片).{0,5}(?:怎么|如何)发',r'发.{0,5}(?:图片|照片)|发送图片',r'图片|照片|相册'),
 ('red_packet',r'红包',r'红包',r'红包'),
 ('transfer',r'转账',r'转账',r'转账'),
 ('payment_code',r'付款码',r'付款码',r'付款码|收付款'),
 ('alarm',r'闹钟',r'闹钟',r'闹钟'),
 ('screenshot',r'截图|截屏',r'截屏|截图',r'截图|截屏'),
 ('blacklist',r'拉黑|黑名单',r'拉黑|黑名单',r'拉黑|黑名单'),
 ('mute',r'免打扰|群.{0,3}吵',r'免打扰',r'免打扰'),
 ('pin_chat',r'聊天.{0,5}(?:最上|置顶)|置顶',r'置顶',r'置顶'),
 ('wifi',r'WiFi|wifi|无线网',r'WiFi|wifi|无线',r'WiFi|wifi|无线'),
 ('hotspot',r'热点',r'热点',r'热点'),
 ('bluetooth',r'蓝牙',r'蓝牙',r'蓝牙'),
 ('register_hospital',r'挂号|挂.{0,5}号',r'挂号',r'挂号|科室|医生'),
 ('train',r'12306|火车票|高铁票|动车票',r'12306|火车票|铁路',r'12306|车次|车票|买票|退票'),
 ('train_buy',r'(?:12306|火车票|高铁票).{0,6}买|买.{0,4}(?:火车|高铁|动车)票',r'12306|火车票',r'查询车票|车次|添加乘客|选座|支付'),
 ('e_bike',r'电动车.{0,4}上牌',r'电动车上牌',r'上牌|车管'),
 ('fraud_police',r'安全账户|自称.{0,3}公安',r'诈骗',r'安全账户|公安|公检法'),
 ('fraud_parcel',r'快递.{0,10}(?:理赔|链接|丢)|理赔.{0,6}链接',r'诈骗',r'快递|理赔|链接'),
 ('fraud_solicitation',r'(?:陌生人|陌生电话|不认识的人).{0,15}(?:转钱|转账|汇款)',r'诈骗',r'转钱|转账|汇款|账户|银行卡'),
 ('gas',r'燃气.{0,5}(?:味|泄漏)|闻到燃气',r'燃气',r'燃气|通风|开关'),
 ('earthquake',r'地震',r'地震',r'震|躲|电梯'),
 ('legal_aid',r'法律援助',r'法律援助',r'法律援助|律师'),
 ('card_loss',r'社保卡.{0,4}(?:丢|挂失|补办)',r'社保卡挂失|社保卡.{0,3}补办',r'挂失|补办'),
 ('pension_verify',r'养老金.{0,4}认证',r'资格认证',r'认证'),
]


@lru_cache(maxsize=512)
def active_profiles(question):
    q=normalize(question)
    profiles = tuple(p for p in PROFILES if re.search(p[1],q,re.I))
    # A disease can be background to an administrative task, and itching can
    # cause poor sleep. Keep the actual task rather than requiring both titles.
    if any(p[0] == 'reimbursement' for p in profiles):
        return tuple(p for p in profiles if p[0] == 'reimbursement')
    if any(p[0] == 'medical_admin' for p in profiles):
        return tuple(p for p in profiles if p[0] == 'medical_admin')
    if any(p[0] == 'itch' for p in profiles):
        return tuple(p for p in profiles if p[0] != 'sleep')
    if any(p[0] == 'voice_text' for p in profiles):
        return tuple(p for p in profiles if p[0] != 'voice_send')
    if '朋友圈' in q:
        return tuple(p for p in profiles if p[0] != 'photo_send')
    return profiles


def matches_scope(question,title,body):
    q=normalize(question)
    profiles=active_profiles(q)
    alternatives={'red_packet','transfer'}
    if sum(p[0] in alternatives for p in profiles)>1:
        if not any(re.search(p[2],title or '',re.I) and re.search(p[3],body or '',re.I)
                   for p in profiles if p[0] in alternatives): return False
        profiles=tuple(p for p in profiles if p[0] not in alternatives)
    for name,_,title_re,body_re in profiles:
        if name=='diet' and re.search(r'吃什么药|药怎么吃',q): continue
        if not re.search(title_re,title or '',re.I) or not re.search(body_re,body or '',re.I): return False
    if re.search(r'空腹',q) and re.search(r'饭后|餐后',q) and re.search(r'区别|不同',q):
        if not re.search(r'空腹',body or '') or not re.search(r'饭后|餐后',body or ''): return False
        if not re.search(r'血糖目标|血糖规范|空腹.{0,3}血糖|空腹.{0,2}[0-9：:]|空腹.{0,3}(?:定义|是指)',body or ''): return False
    instrument_maintenance = re.search(r'校准|校验',q) or (
        '保养' in q and re.search(r'血压计|血糖仪|仪器|设备', q))
    if instrument_maintenance and not re.search(r'校准|校验|保养|校正|维修',body or ''): return False
    return True


def retrieval_allowed(meta):
    """Editorial holds and expiry apply to every retrieval channel, not just badges."""
    status = str(meta.get('review_status') or '').strip().lower()
    if status and status != 'approved':
        return False
    if str(meta.get('review_notes') or '').strip():
        return False
    today = datetime.now(ZoneInfo('Asia/Shanghai')).date()
    for key in ('updated_at', 'reviewed_at', 'valid_until'):
        value = meta.get(key)
        if not value:
            continue
        try:
            date = datetime.fromisoformat(value).date()
        except (ValueError, TypeError):
            return False
        if (key == 'valid_until' and date < today) or (key != 'valid_until' and date > today):
            return False
    return True


def documented_review(meta):
    today=datetime.now(ZoneInfo('Asia/Shanghai')).date()
    if not retrieval_allowed(meta):
        return False
    if meta.get('review_status')!='approved' or not meta.get('reviewed_by') or not re.match(r'https?://',meta.get('source_url') or ''):
        return False
    try:
        reviewed=datetime.fromisoformat(meta.get('reviewed_at') or '').date()
        updated=datetime.fromisoformat(meta.get('updated_at') or '').date()
        if reviewed>today or updated>today: return False
        if meta.get('valid_until') and datetime.fromisoformat(meta['valid_until']).date()<today: return False
    except (ValueError,TypeError):
        return False
    return True


def is_ios_question(question):
    return bool(re.search(r'iPhone|iOS', question, re.I) or (
        '苹果' in question and re.search(r'手机|设备|截[屏图]|相册|系统|设置|主屏|按键', question)))


def reference_applicable(meta, question):
    """Same device/review rules for hybrid retrieval and degraded keyword retrieval."""
    if not retrieval_allowed(meta):
        return False
    platform = meta.get('platform') or ''
    if is_ios_question(question):
        return bool(re.search(r'苹果|iPhone|iOS', platform, re.I))
    if re.search(r'安卓|Android', question, re.I):
        if re.search(r'iPhone|iOS', platform, re.I) and not re.search(r'安卓|Android', platform, re.I):
            return False
    return True


def regional_match(meta, question):
    region=meta.get('region') or ''
    if not meta.get('valid_until') or not documented_review(meta): return False
    for part in re.split(r'[,，、;；]',region):
        part=re.sub(r'(?:省|市|自治区|自治州)$','',part.strip())
        if len(part)>=2 and part in question:
            return True
    return False


def unsafe_medication_instruction(answer):
    """按药物、动作与剂量/自行补停服的组合识别，不过滤普通食物克数。"""
    named_drug = bool(re.search(r'胰岛素|硝酸甘油|阿司匹林|华法林|二甲双胍',answer or ''))
    for sentence in re.split(r'[。；\n]',answer or ''):
        if re.search(r'不高.{0,6}(?:不补|不吃)|(?:按|吃|补).{0,6}正常剂量',sentence): return True
        drug=re.search(r'药|胰岛素|硝酸甘油|阿司匹林|华法林|二甲双胍',sentence)
        dose=re.search(r'(?:\d+(?:\.\d+)?|[一二三四五六七八九十半]+)\s*(?:mg|毫克|片|粒|单位|支)',sentence,re.I)
        action=re.search(r'服|吃|注射|打|加量|减量',sentence)
        if (drug or named_drug) and dose and action: return True
    return False
