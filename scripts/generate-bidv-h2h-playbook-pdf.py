from __future__ import annotations

import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    HRFlowable,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "runbooks" / "bidv-h2h-connection-playbook.md"
OUTPUT = ROOT / "output" / "pdf" / "BIDV-H2H-OpsHub-Connection-Playbook.pdf"

NAVY = colors.HexColor("#17365D")
BLUE = colors.HexColor("#1F5A94")
LIGHT_BLUE = colors.HexColor("#EAF2F8")
LIGHT_GRAY = colors.HexColor("#F5F7FA")
MID_GRAY = colors.HexColor("#64748B")
INK = colors.HexColor("#172033")
ORANGE = colors.HexColor("#C2410C")


def register_fonts() -> None:
    regular = Path(r"C:\Windows\Fonts\arial.ttf")
    bold = Path(r"C:\Windows\Fonts\arialbd.ttf")
    if not regular.exists() or not bold.exists():
        raise RuntimeError("Arial fonts with Vietnamese glyphs are required")
    pdfmetrics.registerFont(TTFont("OpsHub", str(regular)))
    pdfmetrics.registerFont(TTFont("OpsHub-Bold", str(bold)))
    pdfmetrics.registerFontFamily(
        "OpsHub", normal="OpsHub", bold="OpsHub-Bold"
    )


def styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName="OpsHub-Bold",
            fontSize=20,
            leading=25,
            textColor=NAVY,
            alignment=TA_CENTER,
            spaceAfter=10,
        ),
        "h2": ParagraphStyle(
            "H2",
            parent=base["Heading2"],
            fontName="OpsHub-Bold",
            fontSize=13,
            leading=17,
            textColor=BLUE,
            spaceBefore=10,
            spaceAfter=6,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="OpsHub",
            fontSize=9.4,
            leading=14,
            textColor=INK,
            spaceAfter=6,
        ),
        "bullet": ParagraphStyle(
            "Bullet",
            parent=base["BodyText"],
            fontName="OpsHub",
            fontSize=9.2,
            leading=13.5,
            textColor=INK,
            leftIndent=14,
            firstLineIndent=-8,
            bulletIndent=4,
            spaceAfter=4,
        ),
        "code": ParagraphStyle(
            "Code",
            parent=base["Code"],
            fontName="Courier",
            fontSize=7.6,
            leading=10.5,
            leftIndent=7,
            rightIndent=7,
            borderColor=colors.HexColor("#CBD5E1"),
            borderWidth=0.6,
            borderPadding=7,
            backColor=LIGHT_GRAY,
            textColor=INK,
            spaceAfter=7,
        ),
        "small": ParagraphStyle(
            "Small",
            parent=base["BodyText"],
            fontName="OpsHub",
            fontSize=7.6,
            leading=10,
            textColor=MID_GRAY,
            alignment=TA_LEFT,
        ),
        "table": ParagraphStyle(
            "Table",
            parent=base["BodyText"],
            fontName="OpsHub",
            fontSize=7.5,
            leading=10,
            textColor=INK,
        ),
        "table_head": ParagraphStyle(
            "TableHead",
            parent=base["BodyText"],
            fontName="OpsHub-Bold",
            fontSize=7.6,
            leading=10,
            textColor=colors.white,
        ),
    }


def inline(text: str) -> str:
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(
        r"`([^`]+)`",
        r"<font name='OpsHub' color='#475569'>\1</font>",
        text,
    )
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    return text


def table_flowable(lines: list[str], style_map: dict):
    parsed = [[cell.strip() for cell in line.strip().strip("|").split("|")] for line in lines]
    if len(parsed) > 1 and all(re.fullmatch(r":?-{3,}:?", cell) for cell in parsed[1]):
        parsed.pop(1)
    columns = max(len(row) for row in parsed)
    data = []
    for row_index, row in enumerate(parsed):
        row += [""] * (columns - len(row))
        cell_style = style_map["table_head"] if row_index == 0 else style_map["table"]
        data.append([Paragraph(inline(cell), cell_style) for cell in row])
    available = A4[0] - 36 * mm
    weights = [1] * columns
    if columns == 3:
        weights = [1.15, 2.55, 1.4]
    elif columns == 2:
        weights = [1.3, 3.7]
    widths = [available * weight / sum(weights) for weight in weights]
    table = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), NAVY),
                ("BACKGROUND", (0, 1), (-1, -1), colors.white),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT_BLUE]),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#CBD5E1")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


def build_story(markdown: str):
    style_map = styles()
    story = []
    lines = markdown.splitlines()
    index = 0
    in_code = False
    code_lines: list[str] = []
    while index < len(lines):
        raw = lines[index].rstrip()
        if raw.startswith("```"):
            if in_code:
                story.append(Paragraph("<br/>".join(inline(line) for line in code_lines), style_map["code"]))
                code_lines = []
                in_code = False
            else:
                in_code = True
            index += 1
            continue
        if in_code:
            code_lines.append(raw)
            index += 1
            continue
        if raw.startswith("|"):
            table_lines = []
            while index < len(lines) and lines[index].lstrip().startswith("|"):
                table_lines.append(lines[index])
                index += 1
            story.append(table_flowable(table_lines, style_map))
            story.append(Spacer(1, 7))
            continue
        if raw.startswith("# "):
            story.append(Paragraph(inline(raw[2:]), style_map["title"]))
            story.append(HRFlowable(width="100%", thickness=1.4, color=ORANGE, spaceAfter=8))
        elif raw.startswith("## "):
            story.append(Paragraph(inline(raw[3:]), style_map["h2"]))
        elif raw.startswith("- [ ] "):
            story.append(Paragraph("[ ] " + inline(raw[6:]), style_map["bullet"]))
        elif raw.startswith("- "):
            story.append(Paragraph("- " + inline(raw[2:]), style_map["bullet"]))
        elif re.match(r"^\d+\. ", raw):
            number, text = raw.split(". ", 1)
            story.append(Paragraph(f"<b>{number}.</b> {inline(text)}", style_map["bullet"]))
        elif raw.strip():
            story.append(Paragraph(inline(raw.replace("  ", " ")), style_map["body"]))
        else:
            story.append(Spacer(1, 2))
        index += 1
    return story


def page_decor(canvas, doc):
    canvas.saveState()
    width, height = A4
    canvas.setStrokeColor(colors.HexColor("#D5DEE8"))
    canvas.setLineWidth(0.5)
    canvas.line(18 * mm, height - 13 * mm, width - 18 * mm, height - 13 * mm)
    canvas.setFont("OpsHub-Bold", 7.5)
    canvas.setFillColor(NAVY)
    canvas.drawString(18 * mm, height - 10 * mm, "OPSHUB - BIDV H2H")
    canvas.setFont("OpsHub", 7.2)
    canvas.setFillColor(MID_GRAY)
    canvas.drawRightString(width - 18 * mm, height - 10 * mm, "Tài liệu kết nối - Phiên bản 1.0")
    canvas.line(18 * mm, 13 * mm, width - 18 * mm, 13 * mm)
    canvas.drawRightString(width - 18 * mm, 8.5 * mm, f"Trang {doc.page}")
    canvas.restoreState()


def main() -> None:
    register_fonts()
    markdown = SOURCE.read_text(encoding="utf-8")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = BaseDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=20 * mm,
        bottomMargin=18 * mm,
        title="Hướng dẫn kết nối BIDV H2H - OpsHub",
        author="OpsHub",
        subject="OAuth 2.0 và OpenPGP cho BIDV H2H",
    )
    frame = Frame(
        doc.leftMargin,
        doc.bottomMargin,
        doc.width,
        doc.height,
        id="normal",
    )
    doc.addPageTemplates([PageTemplate(id="OpsHub", frames=[frame], onPage=page_decor)])
    doc.build(build_story(markdown))
    print(f"Generated {OUTPUT}")


if __name__ == "__main__":
    main()
