import gradio as gr

USE_MOCK = False
API_URL = "http://127.0.0.1:8000/api/chat"

def mock_ask(query):
    return {
        "answer": f"已收到您的问题：{query}，这是演示回答，等后端Ollama下完会自动换成真实回答。",
        "module": "services",
        "steps": ["第一步：慢慢说出您的需求", "第二步：查看下方分步操作", "第三步：如需帮助请找社区工作人员"],
        "disclaimer": "温馨提示：以上内容仅供参考，涉及医保、医疗、用药请咨询线下工作人员。"
    }

def ask(query, image):
    if not query or not query.strip():
        return "请输入您的问题再点提问哦。", "", ""
    if USE_MOCK:
        data = mock_ask(query)
    else:
        import requests, base64
        payload = {"question": query}
        if image is not None:
            with open(image, "rb") as f:
                payload["image_base64"] = base64.b64encode(f.read()).decode()
        r = requests.post(API_URL, json=payload, timeout=60)
        data = r.json()
    head = {"phone": "手机使用", "services": "便民服务", "daily_life": "日常生活"}.get(data.get("module", ""), data.get("module", ""))
    answer = f"【{head}】\n{data.get('answer','')}"
    steps = "\n".join([f"**第{i+1}步**：{s}" for i, s in enumerate(data.get("steps", []))])
    return answer, steps, data.get("disclaimer", "")

CSS = """
body, .gradio-container {background: #FFF8F0 !important; }
h1 {font-size: 42px !important; text-align: center; color: #B34000 !important;}
.gr-textbox textarea {font-size: 24px !important; line-height: 1.8 !important;}
button.primary {font-size: 26px !important; min-height: 70px !important; border-radius: 16px !important; background: #E65100 !important;}
.output-box textarea {font-size: 24px !important; line-height: 1.9 !important; background: #FFFFFF !important;}
.tip {font-size: 20px; color: #666; background: #FFF3E0; padding: 16px; border-radius: 12px; border-left: 6px solid #E65100;}
"""

with gr.Blocks(title="银龄助手") as demo:
    gr.Markdown("# 👵 银龄数字生活辅助智能体")
    gr.Markdown('<div class="tip">字大、按钮大、慢慢用。输入问题，点橙色大按钮提问。</div>')
    with gr.Row():
        with gr.Column(scale=1):
            inp = gr.Textbox(label="1. 在这里输入您的问题", lines=4, placeholder="例如：怎么在手机上挂号？")
            img = gr.Image(label="2. 上传截图（可选）", type="filepath")
            btn = gr.Button("🔊 提 问", variant="primary")
            clear = gr.ClearButton([inp, img], value="清空重写")
        with gr.Column(scale=1):
            out_a = gr.Textbox(label="回答", lines=10, elem_classes=["output-box"])
            out_s = gr.Markdown(label="分步操作")
            out_d = gr.Markdown(label="温馨提示")
    btn.click(ask, [inp, img], [out_a, out_s, out_d])

    gr.Markdown("示例点一点试试：")
    gr.Examples(["老年机怎么调大字体？", "怎么线上挂号？", "乘车码在哪找？"], inputs=inp)

demo.launch(server_port=7861, css=CSS)