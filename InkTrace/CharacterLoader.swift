//
//  CharacterLoader.swift
//  InkTrace
//
//  Created by 張庭瑄 on 2025/9/10.
//

import Foundation

// MARK: - 字庫 URL 儲存 Key
enum CharacterSourceKeys {
    static let urlKey = "CharacterSourceURL"
    static let cachedTextKey = "CachedCharacterText"
}

// MARK: - 字庫載入管理器
class CharacterLoader: ObservableObject {
    static let shared = CharacterLoader()
    
    @Published var loadedText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    /// 預設字庫（當網址未設定或載入失敗時使用）
    let defaultCharacters: String = """
天地玄黃宇宙洪荒日月盈昃辰宿列張寒來暑往秋收冬藏閏餘成歲律召調陽雲騰致雨露結爲霜金生麗水玉出崑岡劍號巨闕珠稱夜光果珍李柰菜重芥薑海鹹河淡鱗潛羽翔龍師火帝鳥官人皇始制文字乃服衣裳推位讓國有虞陶唐弔民伐罪周發殷湯坐朝問道垂拱平章愛育黎首臣伏戎羌遐邇壹體率賓歸王鳴鳳在樹白駒食場化被草木賴及萬方蓋此身髮四大五常恭惟鞠養豈敢毀傷女慕貞絜男效才良知過必改得能莫忘罔談彼短靡恃己長信使可覆器欲難量墨悲絲淬詩讚羔羊景行維賢克念作聖德建名立形端表正空谷傳聲虛堂習聽禍因惡積福緣善慶尺璧非寶寸陰是競資父事君曰嚴與敬孝當竭力忠則盡命臨深履薄夙興溫凊似蘭斯馨如松之盛川流不息淵澄取映容止若思言辭安定篤初誠美慎終宜令榮業所基籍甚無竟學優登仕攝職從政存以甘棠去而益詠樂殊貴賤禮別尊卑上和下睦夫唱婦隨外受傅訓入奉母儀諸姑伯叔猶子比兒孔懷兄弟同氣連枝交友投分切磨箴規仁慈隱惻造次弗離節義廉退顛沛匪虧性靜情逸心動神疲守眞志滿逐物意移堅持雅操好爵自縻都邑華夏東西二京背邙面洛浮渭據涇宮殿盤鬱樓觀飛驚圖寫禽獸畫彩仙靈丙舍傍啟甲帳對楹肆筵設席鼓瑟吹笙升階納陛弁轉疑星右通廣內左達承明既集墳典亦聚群英杜稾鍾隸漆書壁經府羅將相路俠槐卿戶封八縣家給千兵高冠陪輦驅轂振纓世祿侈富車駕肥輕策功茂實勒碑刻銘磻溪伊尹佐時阿衡奄宅曲阜微旦孰營桓公匡合濟弱扶傾綺迴漢惠說感武丁俊乂密勿多士寔寧晉楚更霸趙魏困橫假途滅虢踐土會盟何遵約法韓弊煩刑起翦頗牧用軍最精宣威沙漠馳譽丹青九州禹跡百郡秦并嶽宗恆岱禪主云亭雁門紫塞雞田赤城昆池碣石鉅野洞庭曠遠綿邈巖岫杳冥治本於農務茲稼穡俶載南畝我藝黍稷稅熟貢新勸賞黜陟孟軻敦素史魚秉直庶幾中庸勞謙謹敕聆音察理鑑貌辨色貽厥嘉猷勉其祗植省躬譏誡寵增抗極殆辱近恥林皋幸即兩疏見機解組誰逼索居閒處沈默寂寥求古尋論散慮逍遙欣奏累遣慼謝歡招渠荷的歷園莽抽條枇杷晚翠梧桐早凋陳根委翳落葉飄颻游鵾獨運凌摩絳霄耽讀翫市寓目囊箱易輶攸畏屬耳垣牆具膳餐飯適口充腸飽飫烹宰飢厭糟糠親戚故舊老少異糧妾御績紡侍巾帷房紈扇圓潔銀燭煒煌晝眠夕
"""
    
    private init() {
        // 初始化時載入快取或預設值
        if let cached = UserDefaults.standard.string(forKey: CharacterSourceKeys.cachedTextKey), !cached.isEmpty {
            loadedText = cached
        } else {
            loadedText = defaultCharacters
        }
    }
    
    /// 取得已儲存的網址
    var savedURL: String {
        get { UserDefaults.standard.string(forKey: CharacterSourceKeys.urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: CharacterSourceKeys.urlKey) }
    }
    
    /// 從網址載入字庫
    func loadFromURL(_ urlString: String, completion: @escaping (Bool, String?) -> Void) {
        guard !urlString.isEmpty else {
            DispatchQueue.main.async {
                self.loadedText = self.defaultCharacters
                completion(true, nil)
            }
            return
        }
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "無效的網址格式"
                completion(false, "無效的網址格式")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "載入失敗：\(error.localizedDescription)"
                    completion(false, self?.errorMessage)
                    return
                }
                
                guard let data = data,
                      let text = String(data: data, encoding: .utf8) else {
                    self?.errorMessage = "無法解析回應內容"
                    completion(false, self?.errorMessage)
                    return
                }
                
                // 移除換行符號，保留所有其他字符
                let cleanedText = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                
                if cleanedText.isEmpty {
                    self?.errorMessage = "檔案內容為空"
                    completion(false, self?.errorMessage)
                    return
                }
                
                self?.loadedText = cleanedText
                self?.savedURL = urlString
                UserDefaults.standard.set(cleanedText, forKey: CharacterSourceKeys.cachedTextKey)
                completion(true, nil)
            }
        }
        task.resume()
    }
    
    /// 清除快取，恢復預設
    func resetToDefault() {
        loadedText = defaultCharacters
        savedURL = ""
        UserDefaults.standard.removeObject(forKey: CharacterSourceKeys.cachedTextKey)
    }
    
    /// 將載入的文字轉換為字元陣列
    var loadedCharacters: [String] {
        return loadedText.map { String($0) }
    }
    
    /// 檢查是否有自訂字庫
    var hasCustomCharacters: Bool {
        return !savedURL.isEmpty && !loadedText.isEmpty
    }
}
