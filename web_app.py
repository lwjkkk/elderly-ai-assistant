import gradio as gr

# ===== MOCK，后端没好之前用这个，好了删掉 =====
def mock_ask(query, image=None):
    return {
        "answer": "这是测试回答，等后端好了会自动替换。",
        "module": "services",
        "steps": ["第一步：打开手机设置", "第二步：找到字体大小", "第三步：调到最大"],
        "disclaimer": "以上内容仅供参考，涉及医保、医疗请咨询线下工作人员。"
    }

USE_MOCK = True  # 联调时改成 False
API_URL = "http://127.0.0.1:8000/api/chat"

def ask(query, image):
    if USE_MOCK:
        data = mock_ask(query, image)
    else:
        import requests
        r = requests.post(API_URL, json={"query": query}, timeout=60)
        data = r.json()

    answer = f"【{data['module']}】\n{data['answer']}"
    steps_md = "\n".join([f"{i+1}. {s}" for i, s in enumerate(data.get("steps", []))])
    return answer, steps_md, data.get("disclaimer", "")

with gr.Blocks(css="* {font-size: 20px} button {min-height: 60px; font-size: 22px}") as demo:
    gr.Markdown("# 银龄数字生活辅助智能体")
    with gr.Row():
        with gr.Column():
            inp = gr.Textbox(label="请输入问题", lines=3, placeholder="例如：怎么挂号？")
            img = gr.Image(label="上传截图（选填）", type="filepath")
            btn = gr.Button("提问", variant="primary")
    with gr.Column():
        out_answer = gr.Textbox(label="回答", lines=8)
        out_steps = gr.Markdown(label="分步操作")
        out_disc = gr.Markdown(label="温馨提示")

    btn.click(ask, [inp, img], [out_answer, out_steps, out_disc])

demo.launch(server_port=7860)
