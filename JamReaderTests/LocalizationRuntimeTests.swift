import XCTest

final class LocalizationRuntimeTests: XCTestCase {
    private struct LocaleExpectation {
        let identifier: String
        let translations: [String: String]
    }

    private let expectations = [
        LocaleExpectation(
            identifier: "en",
            translations: [
                "Browse Pages": "Browse Pages",
                "Complete": "Complete",
                "Current": "Current",
                "Default Folder Import Scope": "Default Folder Import Scope",
                "Download Full Copy While Reading": "Download Full Copy While Reading",
                "Finished": "Finished",
                "Folder": "Folder",
                "General": "General",
                "In progress": "In progress",
                "Latest": "Latest",
                "Library": "Library",
                "Keep Screen Awake": "Keep Screen Awake",
                "Open at Launch": "Open at Launch",
                "Provider": "Provider",
                "Remaining": "Remaining",
                "Review": "Review",
                "Save Page to Photos": "Save Page to Photos",
                "Settings": "Settings",
                "Share": "Share",
                "Strategy": "Strategy",
            ]
        ),
        LocaleExpectation(
            identifier: "zh-Hans",
            translations: [
                "Browse Pages": "浏览页面",
                "Complete": "已收齐",
                "Current": "当前",
                "Default Folder Import Scope": "默认文件夹导入范围",
                "Download Full Copy While Reading": "阅读时下载完整副本",
                "Finished": "已读完",
                "Folder": "文件夹",
                "General": "通用",
                "In progress": "进行中",
                "Latest": "最新",
                "Library": "书库",
                "Keep Screen Awake": "保持屏幕常亮",
                "Open at Launch": "启动时打开",
                "Provider": "连接方式",
                "Remaining": "剩余",
                "Review": "评论",
                "Save Page to Photos": "将页面保存到照片图库",
                "Settings": "设置",
                "Share": "共享名称",
                "Strategy": "导入方式",
            ]
        ),
        LocaleExpectation(
            identifier: "zh-Hant-TW",
            translations: [
                "Browse Pages": "瀏覽頁面",
                "Complete": "已收齊",
                "Current": "目前",
                "Default Folder Import Scope": "預設資料夾匯入範圍",
                "Download Full Copy While Reading": "閱讀時下載完整副本",
                "Finished": "已讀完",
                "Folder": "資料夾",
                "General": "一般",
                "In progress": "進行中",
                "Latest": "最新",
                "Library": "書庫",
                "Keep Screen Awake": "保持螢幕開啟",
                "Open at Launch": "啟動時開啟",
                "Provider": "連線方式",
                "Remaining": "剩餘",
                "Review": "評論",
                "Save Page to Photos": "將頁面儲存到「照片」",
                "Settings": "設定",
                "Share": "共享名稱",
                "Strategy": "匯入方式",
            ]
        ),
        LocaleExpectation(
            identifier: "ja",
            translations: [
                "Browse Pages": "ページ一覧",
                "Complete": "全巻揃い",
                "Current": "現在",
                "Default Folder Import Scope": "デフォルトのフォルダインポート範囲",
                "Download Full Copy While Reading": "閲覧中に完全なコピーをダウンロード",
                "Finished": "読了",
                "Folder": "フォルダ",
                "General": "一般",
                "In progress": "進行中",
                "Latest": "最新",
                "Library": "ライブラリ",
                "Keep Screen Awake": "画面をスリープさせない",
                "Open at Launch": "起動時に開く",
                "Provider": "接続方式",
                "Remaining": "残り",
                "Review": "レビュー",
                "Save Page to Photos": "ページを「写真」に保存",
                "Settings": "設定",
                "Share": "共有名",
                "Strategy": "インポート方法",
            ]
        ),
    ]

    func testRequiredLocalizationsAreBundledAndReadable() throws {
        for expectation in expectations {
            let localizedBundle = try localizedBundle(for: expectation.identifier)

            for (key, expectedValue) in expectation.translations.sorted(by: { $0.key < $1.key }) {
                XCTAssertEqual(
                    localizedString(key, in: localizedBundle),
                    expectedValue,
                    "Unexpected \(key) translation for \(expectation.identifier)"
                )
            }

            let photoPermission = localizedBundle.localizedString(
                forKey: "NSPhotoLibraryAddUsageDescription",
                value: nil,
                table: "InfoPlist"
            )
            XCTAssertFalse(
                photoPermission.isEmpty || photoPermission == "NSPhotoLibraryAddUsageDescription",
                "Missing photo-library permission translation for \(expectation.identifier)"
            )
        }
    }

    private func localizedString(_ key: String, in bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    private func localizedBundle(for identifier: String) throws -> Bundle {
        let appBundle = [Bundle(identifier: "ooou.fun.jamreader"), Bundle.main]
            .compactMap { $0 }
            .first { $0.url(forResource: identifier, withExtension: "lproj") != nil }
        let resourceURL = try XCTUnwrap(
            appBundle?.url(forResource: identifier, withExtension: "lproj"),
            "Missing \(identifier).lproj in the app bundle"
        )
        return try XCTUnwrap(
            Bundle(url: resourceURL),
            "Unable to open \(identifier).lproj"
        )
    }
}
