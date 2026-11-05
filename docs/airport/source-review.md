# 機場落客資料核對（2026-11-04）

原始表：使用者 Downloads/航司落客區表.md（54 行）。只讀，未更改原檔。
正式匯入：香港國際機場官方中英文航司目錄，共 95 間。

- 英文來源：https://www.hongkongairport.com/en/flights/airlines-information/airlines.page
- 中文來源：https://www.hongkongairport.com/tc/flights/airlines-information/airlines.page
- 國泰官方停運港龍聲明：https://news.cathaypacific.com/cathay-pacific-group-announces-corporate-restructuring-351811
- 香港快運官方 T2 行段 U：https://www.hkexpress.com/en/travel-help/HK-Express-Has-Relocated-to-Terminal-2-at-Hong-Kong-International-Airport

## 原表差異

| 代碼 | 原資料 | 官方目錄 |
| --- | --- | --- |
| CX | T1 A/B/C | T1 B/C |
| AC | T1 D | T1 H |
| 5J | T1 D | T2 P/R |
| SU | T1 E | T1 K |
| MH | T1 F | T1 H |
| TG | T1 F | T1 H |
| JX | T1 F | T1 H |
| QF | T1 E | T1 J |
| NZ | T1 E | T1 H |
| LX | T1 E | T1 F |
| VN | T1 E | T1 H |
| PG | T1 F | T2 V |
| AY | T1 F | T1 H |
| LH | T1 E | T1 F |
| QR | T1 G | T1 E |
| AI | T1 G | T1 E |
| TK | T1 G | T1 K |
| KA | 港龍航空 | 不在現行官方目錄，未匯入 |
| DL | T1 G | T1 D |
| VS | 維珍大西洋 | 不在現行官方目錄，未匯入 |
| ET | T1 G | T1 K |
| OZ | T1 J | T1 E |
| ZH | T1 J | T1 H |
| NH | T1 K | T1 E |
| JL | T1 K | T1 G |
| UO | T2 U/V | T2 U |
| I5 | 印尼亞航 | 不在現行官方目錄，未匯入 |

## 尚待核實

原表全數落客區坐標偏離實際 T1/T2 約 7 公里，未匯入。Zone／行段關係以使用者明確確認的原表規則作建議，與官方核對的航司／大樓／行段資料分開標示來源。
後續使用者確認以原表的櫃位至 Zone 規則提供建議。現已為 92 間航司配對；其餘 5J、PG、7C 的原表規則缺失或有歧義，另見 missing-zone-mappings.md。已移除一般「待核實」字樣；只有無配對的航司顯示「暫未提供落客區」。錯誤坐標仍不匯入。
使用者後續明確批准按其地圖草圖加入大約落客區位置。現沿公開道路幾何加入 T1 Zone 1–5、T2 Zone 6–9，並清楚標為大約位置；導航距離計至該大約位置。原表錯誤坐標仍不使用，詳見 zone-coordinates.md。
待取得可靠現場／官方 Zone 點位及行段對應後，補入 Zone 和點位。
航司代碼包含數字，例如 5J、D7、Z2。只使用代碼作一般查詢，不能判定代碼共享航班的實際營運航司。
官方目錄屬當日快照，不是即時航班 API；需要定期重新核對。
