//
//  SharePreprocessor.js
//  ShareExtension
//
//  仕様書 SE-02 / 4.1: JavaScript Preprocessing.
//  Safari が表示中のページから DOM・og:* メタタグ・選択テキストを取り出し,
//  Share Extension へ引き渡す.
//
//  仕様書 SE-04 に従い, HTML は 2MB で切り詰める（Extension のメモリ上限は約 120MB）.
//

var ShareExtensionPreprocessor = function() {};

ShareExtensionPreprocessor.prototype = {
  run: function(args) {
    var meta = {};

    // property 属性（og:*, article:*）と name 属性（author, description）の両方を拾う.
    document.querySelectorAll('meta').forEach(function(element) {
      var key = element.getAttribute('property') || element.getAttribute('name');
      var content = element.getAttribute('content');
      if (key && content) {
        meta[key] = content;
      }
    });

    // 仕様書 16.2 手順 6: canonical があれば正規化の基準として渡す.
    var canonical = document.querySelector('link[rel="canonical"]');
    if (canonical && canonical.href) {
      meta['canonical'] = canonical.href;
    }

    var html = document.documentElement.outerHTML;
    var MAX = 2 * 1024 * 1024;

    args.completionFunction({
      url: document.URL,
      title: document.title,
      meta: meta,
      selection: window.getSelection().toString(),
      html: html.length > MAX ? html.substring(0, MAX) : html
    });
  },

  finalize: function(args) {}
};

var ExtensionPreprocessingJS = new ShareExtensionPreprocessor();
