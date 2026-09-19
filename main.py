from fastapi import FastAPI
import uvicorn

app = FastAPI(title="老年数字辅助智能体后端")

@app.get("/")
def read_root():
    return {"message": "你好，老年智能体后端启动成功！"}

@app.get("/hello/{name}")
def say_hello(name: str):
    return {"message": f"你好 {name}，我是老年数字辅助智能体"}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)