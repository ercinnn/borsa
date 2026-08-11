// Yahoo Finance'in "en çok işlem gören" ekran tarayıcısı kimlik doğrulama
// (crumb/cookie) gerektirdiği ve güvenilir olmadığı için, BIST ve ABD
// listeleri burada küratörlü/statik olarak tutuluyor. Endeks/piyasa
// bileşimi zamanla değiştiğinden bu listeler dönemsel bir anlık görüntüdür;
// yanlış veya güncelliğini yitirmiş bir sembol olsa bile kontrol servisi
// o sembolü sessizce atlar (checkAll tek sembol hatasında durmaz).
//
// cryptoFallbackSymbols aynı mantıkla, ama farklı bir amaçla var: normalde
// kripto listesi CoinGecko'dan canlı çekilir (bkz. coingecko_client.dart);
// bu liste sadece CoinGecko rate limit/erişim sorunu yüzünden tamamen
// başarısız olduğunda son çare yedek olarak kullanılır. 300'den az öğe
// içeriyor olması kasıtlı — canlı crypto300 preset'i normalde zaten
// CoinGecko'dan gelir, bu sadece "hiç Yahoo'ya gidilemese bile en azından
// bir şey göster" amaçlı, tam 300'e tamamlanması gerekmiyor.

const bist200Symbols = [
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
  // İkinci 100 — BIST TÜM endeksindeki diğer bilinen/likit şirketler
  // (kaynak: uzmanpara.milliyet.com.tr güncel BIST sembol listesi).
  'AKCNS.IS', 'AKFGY.IS', 'AKFYE.IS', 'AKGRT.IS', 'AKSGY.IS', 'ALBRK.IS',
  'ALKIM.IS', 'ARENA.IS', 'ARZUM.IS', 'AYDEM.IS', 'AYGAZ.IS', 'BAGFS.IS',
  'BANVT.IS', 'BASGZ.IS', 'BERA.IS', 'BIENY.IS', 'BIOEN.IS', 'BIZIM.IS',
  'BJKAS.IS', 'BOSSA.IS', 'BRISA.IS', 'BRLSM.IS', 'BSOKE.IS', 'CEMTS.IS',
  'CLEBI.IS', 'CRFSA.IS', 'CUSAN.IS', 'DAGI.IS', 'DERIM.IS', 'DESA.IS',
  'DEVA.IS', 'DGATE.IS', 'DGGYO.IS', 'DOKTA.IS', 'ECZYT.IS', 'EDIP.IS',
  'EGSER.IS', 'EKIZ.IS', 'ENERY.IS', 'ERCB.IS', 'ESCOM.IS', 'FONET.IS',
  'FORTE.IS', 'GEDIK.IS', 'GENTS.IS', 'GLRYH.IS', 'GOODY.IS', 'GOZDE.IS',
  'GRSEL.IS', 'GSDHO.IS', 'GUNDG.IS', 'HATEK.IS', 'HLGYO.IS', 'HUBVC.IS',
  'HURGZ.IS', 'ICBCT.IS', 'IHLAS.IS', 'INDES.IS', 'INTEM.IS', 'INVES.IS',
  'ISFIN.IS', 'ISMEN.IS', 'IZFAS.IS', 'JANTS.IS', 'KAPLM.IS', 'KARTN.IS',
  'KATMR.IS', 'KBORU.IS', 'KENT.IS', 'KERVN.IS', 'KLGYO.IS', 'KLKIM.IS',
  'KLMSN.IS', 'KLRHO.IS', 'KNFRT.IS', 'KONKA.IS', 'KOPOL.IS', 'KRPLS.IS',
  'KRSTL.IS', 'KUYAS.IS', 'LIDFA.IS', 'LINK.IS', 'LKMNH.IS', 'LUKSK.IS',
  'MAGEN.IS', 'MAKIM.IS', 'MANAS.IS', 'MARKA.IS', 'MARTI.IS', 'MEDTR.IS',
  'MEPET.IS', 'MERKO.IS', 'METRO.IS', 'MNDRS.IS', 'MOBTL.IS', 'NATEN.IS',
  'NETAS.IS', 'NUHCM.IS', 'OBASE.IS', 'ORGE.IS',
];

const usPopular200Symbols = [
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
  // İkinci 95 — S&P 500'den ek büyük/orta ölçekli şirketler (105 + 95 = 200).
  'WM', 'APD', 'CME', 'FDX', 'NSC', 'PSA', 'AIG', 'MET', 'AFL', 'TRV',
  'PNC', 'USB', 'TFC', 'COF', 'MSI', 'ROP', 'CTAS', 'FIS', 'ADSK',
  'NXPI', 'LRCX', 'KLAC', 'AMAT', 'MCHP', 'ON', 'CDNS', 'WDAY', 'NOW',
  'PANW', 'FTNT', 'CRWD', 'TEAM', 'DDOG', 'SNOW', 'UBER', 'ABNB', 'BKNG',
  'MAR', 'HLT', 'YUM', 'CMG', 'DPZ', 'EXC', 'AEP', 'D', 'SRE', 'XEL',
  'ED', 'WEC', 'PEG', 'EIX', 'PPL', 'FE', 'ES', 'AEE', 'CMS', 'DTE',
  'ATO', 'NI', 'LNT', 'EVRG', 'PNW', 'NRG', 'VST', 'CEG', 'PCG', 'WMB',
  'KMI', 'OKE', 'PSX', 'VLO', 'MPC', 'HAL', 'BKR', 'DVN', 'FANG', 'CTRA',
  'HES', 'APA', 'MRO', 'COP', 'OXY', 'WELL', 'O', 'SPG', 'AMT', 'CCI',
  'DLR', 'EXR', 'AVB', 'EQR', 'VTR', 'DAL', 'CSX', 'KMB',
];

const cryptoFallbackSymbols = [
  'BTC-USD', 'ETH-USD', 'USDT-USD', 'XRP-USD', 'BNB-USD', 'SOL-USD',
  'USDC-USD', 'DOGE-USD', 'ADA-USD', 'TRX-USD', 'WBTC-USD', 'LINK-USD',
  'AVAX-USD', 'SUI-USD', 'XLM-USD', 'TON-USD', 'SHIB-USD', 'HBAR-USD',
  'BCH-USD', 'DOT-USD', 'LEO-USD', 'LTC-USD', 'XMR-USD', 'DAI-USD',
  'UNI-USD', 'PEPE-USD', 'AAVE-USD', 'TAO-USD', 'APT-USD', 'NEAR-USD',
  'ETC-USD', 'OKB-USD', 'ICP-USD', 'MNT-USD', 'CRO-USD', 'KAS-USD',
  'MATIC-USD', 'VET-USD', 'ALGO-USD', 'RENDER-USD', 'ATOM-USD', 'FIL-USD',
  'TIA-USD', 'ARB-USD', 'FET-USD', 'STX-USD', 'IMX-USD', 'INJ-USD',
  'OP-USD', 'WLD-USD', 'THETA-USD', 'RUNE-USD', 'GRT-USD', 'FLOW-USD',
  'LDO-USD', 'SEI-USD', 'JUP-USD', 'PYTH-USD', 'KAVA-USD', 'QNT-USD',
  'XTZ-USD', 'MKR-USD', 'EGLD-USD', 'SAND-USD', 'MANA-USD', 'AXS-USD',
  'CHZ-USD', 'GALA-USD', 'ZEC-USD', 'EOS-USD', 'XEC-USD', 'NEO-USD',
  'KCS-USD', 'FTM-USD', 'MINA-USD', 'KLAY-USD', 'WAVES-USD', 'ENJ-USD',
  'BAT-USD', 'ZIL-USD', 'ANKR-USD', 'COMP-USD', 'SNX-USD', 'CRV-USD',
  '1INCH-USD', 'YFI-USD', 'SUSHI-USD', 'DYDX-USD', 'GMX-USD', 'LRC-USD',
  'OCEAN-USD', 'ROSE-USD', 'CELO-USD', 'IOTA-USD', 'XDC-USD', 'GNO-USD',
  'BAL-USD', 'REN-USD', 'KNC-USD', 'STORJ-USD', 'SKL-USD', 'ANT-USD',
  'BAND-USD', 'CVC-USD', 'NMR-USD', 'UMA-USD', 'RSR-USD', 'POWR-USD',
  'OXT-USD', 'NKN-USD', 'DENT-USD', 'HOT-USD', 'ICX-USD', 'ONT-USD',
  'QTUM-USD', 'ZRX-USD', 'RVN-USD', 'SC-USD', 'DGB-USD', 'DCR-USD',
  'LSK-USD', 'NANO-USD', 'XVG-USD', 'BTG-USD', 'ZEN-USD', 'XEM-USD',
  'WAXP-USD', 'ELF-USD', 'CELR-USD', 'COTI-USD', 'ONE-USD', 'IOST-USD',
  'HIVE-USD', 'STEEM-USD', 'ARDR-USD', 'PIVX-USD', 'VTHO-USD', 'GAS-USD',
  'WTC-USD', 'REP-USD', 'MTL-USD', 'DASH-USD', 'FLR-USD', 'AKT-USD',
  'JASMY-USD', 'ORDI-USD', 'BONK-USD', 'WIF-USD', 'FLOKI-USD', 'PENDLE-USD',
  'ENS-USD', 'BLUR-USD', 'CFX-USD', 'MASK-USD', 'API3-USD', 'ILV-USD',
  'AUDIO-USD', 'SXP-USD', 'ALPHA-USD', 'RLC-USD', 'CTSI-USD',
  'STRK-USD', 'W-USD', 'ETHFI-USD', 'ENA-USD', 'ZK-USD', 'NOT-USD',
];
