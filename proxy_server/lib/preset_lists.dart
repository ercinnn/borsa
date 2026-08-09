// Yahoo Finance'in "en çok işlem gören" ekran tarayıcısı kimlik doğrulama
// (crumb/cookie) gerektirdiği ve güvenilir olmadığı için, BIST ve ABD
// listeleri burada küratörlü/statik olarak tutuluyor. Endeks/piyasa
// bileşimi zamanla değiştiğinden bu listeler dönemsel bir anlık görüntüdür;
// yanlış veya güncelliğini yitirmiş bir sembol olsa bile kontrol servisi
// o sembolü sessizce atlar (checkAll tek sembol hatasında durmaz).

const bist100Symbols = [
  'THYAO.IS', 'ASELS.IS', 'GARAN.IS', 'AKBNK.IS', 'ISCTR.IS', 'YKBNK.IS',
  'SAHOL.IS', 'KCHOL.IS', 'SASA.IS', 'EREGL.IS', 'BIMAS.IS', 'TUPRS.IS',
  'PETKM.IS', 'TOASO.IS', 'FROTO.IS', 'TTKOM.IS', 'TCELL.IS', 'PGSUS.IS',
  'MGROS.IS', 'ARCLK.IS', 'VESTL.IS', 'VESBE.IS', 'ENKAI.IS', 'HALKB.IS',
  'VAKBN.IS', 'TSKB.IS', 'ALARK.IS', 'DOHOL.IS', 'EKGYO.IS', 'KOZAL.IS',
  'KOZAA.IS', 'GUBRF.IS', 'SISE.IS', 'KRDMD.IS', 'ODAS.IS', 'AEFES.IS',
  'ULKER.IS', 'CCOLA.IS', 'TAVHL.IS', 'OTKAR.IS', 'TKFEN.IS', 'ZOREN.IS',
  'IPEKE.IS', 'GESAN.IS', 'ASTOR.IS', 'KONTR.IS', 'SMRTG.IS', 'EUPWR.IS',
  'CIMSA.IS', 'AKSA.IS', 'AKSEN.IS', 'AGHOL.IS', 'ALFAS.IS', 'ANHYT.IS',
  'ANSGR.IS', 'BRSAN.IS', 'BRYAT.IS', 'BUCIM.IS', 'CANTE.IS', 'CWENE.IS',
  'DOAS.IS', 'ECILC.IS', 'EGEEN.IS', 'ENJSA.IS', 'EUREN.IS', 'FENER.IS',
  'GENIL.IS', 'GLYHO.IS', 'GWIND.IS', 'HEKTS.IS', 'ISDMR.IS', 'ISGYO.IS',
  'IZMDC.IS', 'KARSN.IS', 'KAYSE.IS', 'KLSER.IS', 'KMPUR.IS', 'KONYA.IS',
  'KORDS.IS', 'LOGO.IS', 'MAVI.IS', 'MIATK.IS', 'MPARK.IS', 'NTHOL.IS',
  'OYAKC.IS', 'PENTA.IS', 'PSGYO.IS', 'SDTTR.IS', 'SELEC.IS', 'SKBNK.IS',
  'SOKM.IS', 'TATGD.IS', 'TMSN.IS', 'TRGYO.IS', 'TUKAS.IS', 'TURSG.IS',
  'TTRAK.IS', 'YATAS.IS', 'ZRGYO.IS', 'QUAGR.IS',
];

const usPopular100Symbols = [
  'AAPL', 'MSFT', 'GOOGL', 'GOOG', 'AMZN', 'NVDA', 'META', 'TSLA', 'BRK-B',
  'LLY', 'AVGO', 'JPM', 'V', 'UNH', 'XOM', 'MA', 'PG', 'COST', 'HD', 'MRK',
  'ABBV', 'CVX', 'PEP', 'KO', 'ADBE', 'WMT', 'CRM', 'BAC', 'MCD', 'NFLX',
  'TMO', 'ACN', 'LIN', 'CSCO', 'ABT', 'DIS', 'PFE', 'WFC', 'INTC', 'VZ',
  'CMCSA', 'TXN', 'AMD', 'PM', 'NKE', 'DHR', 'NEE', 'RTX', 'UPS', 'UNP',
  'BMY', 'ORCL', 'QCOM', 'HON', 'LOW', 'IBM', 'SPGI', 'CAT', 'GE', 'AMGN',
  'INTU', 'BA', 'DE', 'PLD', 'GS', 'ELV', 'SBUX', 'MDT', 'BLK', 'ISRG',
  'GILD', 'AXP', 'ADP', 'MDLZ', 'LMT', 'SYK', 'C', 'MMC', 'ADI', 'VRTX',
  'TJX', 'CB', 'MO', 'SCHW', 'ZTS', 'CVS', 'REGN', 'SO', 'BDX', 'PGR',
  'DUK', 'CI', 'BSX', 'ETN', 'AON', 'MU', 'EOG', 'NOC', 'SLB', 'PYPL',
  'ITW', 'SNPS', 'GD', 'EQIX', 'TGT',
];
