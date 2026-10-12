// Easyl iOS 演示源 —— 同时作为「源脚本协议」的参考实现
// 入口：home / search / detail / play / danmaku
// 运行时：req(url, options) / post(url, body, options) / console.log / cache / local / kits / app

var appName = "演示源";
var appVersion = "1.0";

var SAMPLES = [
    { id: "demo-hls", title: "Apple 测试流（HLS）", poster: "", remark: "HLS", year: "2024", type: "测试" },
    { id: "demo-mp4", title: "MP4 直链示例", poster: "", remark: "点播", year: "2024", type: "测试" },
    { id: "demo-danmaku", title: "弹幕演示", poster: "", remark: "弹幕", year: "2024", type: "测试" }
];

var TEST_HLS = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8";

function home() {
    console.log("demo home called", app.platform);
    return {
        sections: [
            { title: "演示内容", items: SAMPLES },
            { title: "推荐（同一组数据）", items: SAMPLES.slice(0, 2) }
        ]
    };
}

function search(keyword, page) {
    var key = String(keyword || "").toLowerCase();
    var items = SAMPLES.filter(function (item) {
        return item.title.toLowerCase().indexOf(key) >= 0;
    });
    return { items: items, hasMore: false };
}

function detail(id) {
    return {
        title: "演示条目 " + id,
        poster: "",
        desc: "内置演示：用于验证 JS 源引擎（JavaScriptCore）、播放器（AVPlayer）、弹幕渲染是否全部正常。真实源按同样的结构返回即可。",
        year: "2024",
        lines: [
            {
                name: "默认线路",
                episodes: [
                    { name: "第 1 集", id: id + "|1", flag: "默认线路" },
                    { name: "第 2 集", id: id + "|2", flag: "默认线路" },
                    { name: "第 3 集", id: id + "|3", flag: "默认线路" }
                ]
            },
            {
                name: "备用线路",
                episodes: [
                    { name: "第 1 集", id: id + "|1", flag: "备用线路" }
                ]
            }
        ]
    };
}

function play(flag, id) {
    var info = { url: TEST_HLS, type: "hls", headers: {}, danmakuId: id, danmakuName: appName };
    // 需要鉴权的源可以这样带请求头：
    // info.headers = { "Referer": "https://example.com/", "User-Agent": "Mozilla/5.0" };
    return info;
}

function danmaku(id, name) {
    var comments = [];
    for (var i = 0; i < 40; i++) {
        comments.push({
            text: "演示弹幕 #" + (i + 1),
            time: 2 + i * 1.2,
            mode: (i % 9 === 0) ? "top" : ((i % 13 === 0) ? "bottom" : "scroll"),
            color: (i % 5 === 0) ? "#FFD54F" : "#FFFFFF"
        });
    }
    return { comments: comments };
}
