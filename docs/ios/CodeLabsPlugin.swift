//
//  CodeLabsPlugin.swift
//  iOS-реализация кастомного Capacitor-плагина "CodeLabs".
//
//  Android-аналог: studio.codelabs.mobile.CodeLabsPlugin
//  Контракт взят из веб-бандла Code Labs 1.6.2:
//      CodeLabs.openExternal({ url })
//      CodeLabs.printHtml({ html, name })
//
//  Куда положить: ios/App/App/CodeLabsPlugin.swift
//  (добавить в target "App" в Xcode; при сборке через CI файл подхватится сам,
//   потому что Capacitor сканирует рантайм на подклассы CAPPlugin)
//

import Foundation
import UIKit
import Capacitor

@objc(CodeLabsPlugin)
public class CodeLabsPlugin: CAPPlugin, CAPBridgedPlugin {

    // jsName должен совпадать с именем, под которым плагин зовут из JS:
    // registerPlugin("CodeLabs") -> jsName = "CodeLabs"
    public let identifier = "CodeLabsPlugin"
    public let jsName = "CodeLabs"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "openExternal", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "printHtml",    returnType: CAPPluginReturnPromise),
    ]

    private static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    /// Открыть ссылку во внешнем браузере.
    /// Android: startActivity(Intent(Intent.ACTION_VIEW, uri))
    /// iOS:     UIApplication.shared.open(url)
    @objc func openExternal(_ call: CAPPluginCall) {
        guard let raw = call.getString("url"), let url = URL(string: raw) else {
            call.reject("Не передан корректный параметр url")
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        guard Self.allowedSchemes.contains(scheme) else {
            call.reject("Схема «\(scheme)» не разрешена")
            return
        }

        DispatchQueue.main.async {
            guard UIApplication.shared.canOpenURL(url) else {
                call.reject("Система не может открыть \(raw)")
                return
            }
            UIApplication.shared.open(url, options: [:]) { opened in
                if opened {
                    call.resolve()
                } else {
                    call.reject("Не удалось открыть \(raw)")
                }
            }
        }
    }

    /// Печать HTML (и «Сохранить в PDF» через системный диалог печати).
    /// Android: WebView.createPrintDocumentAdapter() + PrintManager.print()
    /// iOS:     UIMarkupTextPrintFormatter + UIPrintInteractionController
    @objc func printHtml(_ call: CAPPluginCall) {
        guard let html = call.getString("html"), !html.isEmpty else {
            call.reject("Не передан параметр html")
            return
        }
        let jobName = call.getString("name") ?? "Code Labs"

        DispatchQueue.main.async { [weak self] in
            let controller = UIPrintInteractionController.shared

            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = jobName
            info.orientation = .portrait
            controller.printInfo = info
            controller.showsNumberOfCopies = false

            let formatter = UIMarkupTextPrintFormatter(markupText: html)
            // ~12.7 мм со всех сторон — как Margins в Android-версии.
            formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
            controller.printFormatter = formatter

            let completion: UIPrintInteractionController.CompletionHandler = { _, completed, error in
                if let error {
                    call.reject("Печать не удалась: \(error.localizedDescription)")
                } else {
                    // completed == false, если пользователь закрыл диалог. Это не ошибка.
                    call.resolve(["completed": completed])
                }
            }

            // На iPad диалог печати обязан быть привязан к области экрана,
            // иначе present(animated:) роняет приложение.
            if UIDevice.current.userInterfaceIdiom == .pad,
               let view = self?.bridge?.viewController?.view {
                let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                controller.present(from: anchor, in: view, animated: true, completionHandler: completion)
            } else {
                controller.present(animated: true, completionHandler: completion)
            }
        }
    }
}
