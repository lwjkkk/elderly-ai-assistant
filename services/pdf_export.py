# PDF 导出服务：用 reportlab 生成体征趋势 PDF
# 包含：标题、趋势图（matplotlib 绘制后嵌入）、数据表、免责声明

import io
import os
import tempfile
from datetime import datetime
from xml.sax.saxutils import escape

from db.models import Vitals


def generate_vitals_pdf(records: list[Vitals], elder_name: str, disclaimer: str) -> bytes:
    """生成体征 PDF，返回 bytes。"""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    # 注册中文字体（优先用系统字体）
    font_name = _register_chinese_font()

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4,
                            topMargin=20 * mm, bottomMargin=20 * mm,
                            leftMargin=15 * mm, rightMargin=15 * mm)
    styles = getSampleStyleSheet()

    # 自定义标题样式
    title_style = ParagraphStyle(
        "ChineseTitle", parent=styles["Title"],
        fontName=font_name, fontSize=16, spaceAfter=10,
    )
    normal_style = ParagraphStyle(
        "ChineseNormal", parent=styles["Normal"],
        fontName=font_name, fontSize=10,
    )

    elements = []

    # 标题
    elements.append(Paragraph(f"{escape(str(elder_name))} 的体征记录", title_style))
    elements.append(Paragraph(f"导出时间：{datetime.now().strftime('%Y-%m-%d %H:%M')}", normal_style))
    elements.append(Spacer(1, 10 * mm))

    # 趋势图（如果有血压数据）
    bp_records = [r for r in records if r.type == "bp"]
    chart_path = None
    if bp_records:
        chart_path = _draw_bp_chart(bp_records)
        if chart_path and os.path.exists(chart_path):
            elements.append(Paragraph("血压趋势图", normal_style))
            elements.append(Spacer(1, 3 * mm))
            elements.append(Image(chart_path, width=170 * mm, height=80 * mm))
            elements.append(Spacer(1, 5 * mm))

    # 数据表
    elements.append(Paragraph("详细数据", normal_style))
    elements.append(Spacer(1, 3 * mm))

    table_data = [["日期", "类型", "数值"]]
    for r in records:
        date_str = r.measured_at.strftime("%Y-%m-%d %H:%M") if r.measured_at else "-"
        type_map = {"bp": "血压", "bs": "血糖", "hr": "心率", "weight": "体重"}
        type_name = type_map.get(r.type, r.type)

        if r.type == "bp" and r.systolic is not None and r.diastolic is not None:
            value_str = f"{r.systolic}/{r.diastolic} mmHg"
        elif r.value is not None:
            unit_map = {"bs": " mmol/L", "hr": " bpm", "weight": " kg"}
            value_str = f"{r.value}{unit_map.get(r.type, '')}"
        else:
            value_str = "-"

        table_data.append([date_str, type_name, value_str])

    col_widths = [55 * mm, 30 * mm, 75 * mm]
    table = Table(table_data, colWidths=col_widths)
    table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), font_name),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("BACKGROUND", (0, 0), (-1, 0), colors.grey),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.lightgrey]),
    ]))
    elements.append(table)
    elements.append(Spacer(1, 10 * mm))

    # 免责声明
    elements.append(Paragraph("免责声明", normal_style))
    elements.append(Spacer(1, 2 * mm))
    elements.append(Paragraph(escape(disclaimer), ParagraphStyle(
        "Disclaimer", parent=normal_style, fontSize=8, textColor=colors.grey,
    )))

    try:
        doc.build(elements)
    finally:
        # Image 在 build 时才读取文件，成功或失败都清理临时图。
        if chart_path and os.path.exists(chart_path):
            os.remove(chart_path)
    return buf.getvalue()


def _register_chinese_font() -> str:
    """注册可用中文字体；没有系统中文字体时退回 ReportLab 内置字体。"""
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    font_paths = [
        "C:/Windows/Fonts/simhei.ttf",       # 黑体
        "C:/Windows/Fonts/simsun.ttc",       # 宋体
        "C:/Windows/Fonts/msyh.ttc",         # 微软雅黑
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",  # Linux 文泉驿正黑
    ]
    for path in font_paths:
        if os.path.exists(path):
            try:
                font_name = "ChineseFont"
                if font_name not in pdfmetrics.getRegisteredFontNames():
                    pdfmetrics.registerFont(TTFont(font_name, path))
                # 必须注册字体族，否则 Paragraph 解析 bold/italic 时会报
                # "Can't map determine family/bold/italic"
                pdfmetrics.registerFontFamily(
                    "ChineseFont",
                    normal="ChineseFont", bold="ChineseFont",
                    italic="ChineseFont", boldItalic="ChineseFont")
                return font_name
            except Exception:
                continue
    # ReportLab 自带的 CID 字体无需额外字体文件，保证 Linux/容器也能输出中文。
    try:
        from reportlab.pdfbase.cidfonts import UnicodeCIDFont
        cid_font = UnicodeCIDFont("STSong-Light")
        font_name = cid_font.fontName
        if font_name not in pdfmetrics.getRegisteredFontNames():
            pdfmetrics.registerFont(cid_font)
        pdfmetrics.registerFontFamily(
            font_name, normal=font_name, bold=font_name,
            italic=font_name, boldItalic=font_name)
        return font_name
    except Exception:
        # 最后的兼容退路保证导出仍可用，但不保证 CJK 字形。
        return "Helvetica"


def _draw_bp_chart(records: list[Vitals]) -> str | None:
    """用 matplotlib 绘制血压趋势图，返回临时文件路径。"""
    try:
        import matplotlib
        matplotlib.use("Agg")  # 非交互式后端
        import matplotlib.pyplot as plt
        from matplotlib import font_manager

        # 尝试加载中文字体
        font_path = None
        for p in ["C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/msyh.ttc",
                  "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"]:
            if os.path.exists(p):
                font_path = p
                break

        if font_path:
            font_manager.fontManager.addfont(font_path)
            plt.rcParams["font.family"] = font_manager.FontProperties(fname=font_path).get_name()
        else:
            plt.rcParams["font.family"] = "sans-serif"

        dates = []
        systolic = []
        diastolic = []
        for r in records:
            if r.measured_at and r.systolic is not None and r.diastolic is not None:
                dates.append(r.measured_at.strftime("%m/%d"))
                systolic.append(r.systolic)
                diastolic.append(r.diastolic)

        if not dates:
            return None

        fig, ax = plt.subplots(figsize=(8, 3.5))
        ax.plot(dates, systolic, "o-", color="#e74c3c", label="收缩压", linewidth=1.5)
        ax.plot(dates, diastolic, "s-", color="#3498db", label="舒张压", linewidth=1.5)
        ax.axhline(y=140, color="#e74c3c", linestyle="--", alpha=0.3, label="收缩压上限")
        ax.axhline(y=90, color="#3498db", linestyle="--", alpha=0.3, label="舒张压上限")
        ax.set_ylabel("mmHg")
        ax.legend(fontsize=8)
        ax.tick_params(axis="x", rotation=45, labelsize=7)
        plt.tight_layout()

        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        fig.savefig(tmp.name, dpi=120)
        plt.close(fig)
        return tmp.name

    except Exception:
        return None
