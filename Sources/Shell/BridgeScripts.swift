import Foundation

/// 全部注入脚本，逐条对齐 Android 端 `MainActivity.injectNativeBridge()` /
/// `handleNativeBack()` 中 `evaluateJavascript(...)` 的字符串常量。
///
/// 对应关系：
/// - `bridgeJS`  ← injectNativeBridge 第 1 段（__HG_NATIVE_APP__ / HGApp.* / 点击高亮样式）
/// - `patchJS`   ← injectNativeBridge 第 2 段（__HG_PATCH_V1__：fakeVip + stripAds + unlockPlay）
/// - `handleBackJS` ← handleNativeBack
enum BridgeScripts {

    /// 把注入值里的引号剥掉，等价 Android 的 `replace("'", "").replace("\"", "")`；
    /// 额外转义/去除反斜杠与换行，避免值以 `\` 结尾时吃掉 JS 字符串收尾引号。
    static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\u{2028}", with: "")
            .replacingOccurrences(of: "\u{2029}", with: "")
    }

    /// 原生外壳注入脚本（含 iOS 版 HuangGuoNative 桥接层）。
    static func bridgeJS(appVersion: String, apiBase: String, apiBaseBackup: String) -> String {
        let version = sanitize(appVersion)
        let api = sanitize(apiBase)
        let backup = sanitize(apiBaseBackup)
        let backupLine = apiBaseBackup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "window.__HG_API_SEED_BACKUP__='\(backup)';"
        return ##"""
        window.__HG_NATIVE_APP__=1;
        window.__HG_APP_VERSION__='\##(version)';
        window.__HG_API_SEED__='\##(api)';
        \##(backupLine)
        window.__HG_BRIDGE_CACHE__=window.__HG_BRIDGE_CACHE__||{};
        (function(){
          var seq=0;
          var pending={};
          function post(payload){
            try{ window.webkit.messageHandlers.HuangGuoNative.postMessage(JSON.stringify(payload)); return true; }
            catch(e){ return false; }
          }
          window.__HG_BRIDGE_RESOLVE__=function(id,valueJson){
            try{
              var cb=pending[id]; if(!cb){return;}
              delete pending[id];
              cb(valueJson==null?null:JSON.parse(valueJson));
            }catch(e){}
          };
          function invoke(name,args){
            return new Promise(function(resolve){
              var id='hg'+(++seq);
              pending[id]=resolve;
              if(!post({id:id,method:name,args:args||[]})){ delete pending[id]; resolve(null); }
            });
          }
          function cached(name){
            var c=window.__HG_BRIDGE_CACHE__;
            return c.hasOwnProperty(name)?c[name]:'';
          }
          window.HuangGuoNative={
            invoke:invoke,
            checkUpdate:function(){ invoke('checkUpdate',[]); return true; },
            onRouteChange:function(path){ invoke('onRouteChange',[String(path||'')]); return true; },
            onH5SplashReady:function(){ invoke('onH5SplashReady',[]); return true; },
            logEvent:function(name,propsJson){ invoke('logEvent',[String(name||''),propsJson==null?'':String(propsJson)]); return true; },
            logScreen:function(path){ invoke('logScreen',[String(path||'')]); return true; },
            getPromoBindToken:function(){ return String(cached('promoBindToken')||''); },
            getApiBase:function(){ return String(cached('apiBase')||''); },
            getPromoAgentId:function(){ return String(cached('promoAgentId')||''); },
            setPullRefreshEnabled:function(enabled){ invoke('setPullRefreshEnabled',[!!enabled]); return true; },
            setOrientation:function(mode){ invoke('setOrientation',[String(mode||'')]); return true; },
            enterFullscreen:function(){ invoke('enterFullscreen',[]); return true; },
            exitFullscreen:function(){ invoke('exitFullscreen',[]); return true; },
            openUrl:function(url){ invoke('openUrl',[String(url||'')]); return true; }
          };
        })();
        window.HGApp=window.HGApp||{};
        window.HGApp.checkUpdate=function(){
          try{ if(window.HuangGuoNative&&HuangGuoNative.checkUpdate){ HuangGuoNative.checkUpdate(); return true; } }catch(e){}
          return false;
        };
        window.HGApp.syncPullRefresh=function(path){
          try{
            var p=(path||location.pathname||'').toString();
            if(window.HuangGuoNative&&HuangGuoNative.onRouteChange){ HuangGuoNative.onRouteChange(p); return true; }
          }catch(e){}
          return false;
        };
        window.HGApp.notifySplashReady=function(){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.onH5SplashReady){ HuangGuoNative.onH5SplashReady(); return true; }
          }catch(e){}
          return false;
        };
        window.HGApp.logEvent=function(name, propsJson){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.logEvent){
              HuangGuoNative.logEvent(String(name||''), propsJson==null?'':String(propsJson));
              return true;
            }
          }catch(e){}
          return false;
        };
        window.HGApp.logScreen=function(path){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.logScreen){
              HuangGuoNative.logScreen(String(path||location.pathname||'/'));
              return true;
            }
          }catch(e){}
          return false;
        };
        window.HGApp.getPromoBindToken=function(){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.getPromoBindToken){
              return String(HuangGuoNative.getPromoBindToken()||'');
            }
          }catch(e){}
          return '';
        };
        window.HGApp.openUrl=function(url){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.openUrl){
              HuangGuoNative.openUrl(String(url||'')); return true;
            }
          }catch(e){}
          return false;
        };
        window.HGApp.setPullRefreshEnabled=function(enabled){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.setPullRefreshEnabled){ HuangGuoNative.setPullRefreshEnabled(enabled); return true; }
          }catch(e){}
          return false;
        };
        window.HGApp.setOrientation=function(mode){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.setOrientation){ HuangGuoNative.setOrientation(String(mode||'')); return true; }
          }catch(e){}
          return false;
        };
        window.HGApp.enterFullscreen=function(){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.enterFullscreen){ HuangGuoNative.enterFullscreen(); return true; }
          }catch(e){}
          return false;
        };
        window.HGApp.exitFullscreen=function(){
          try{
            if(window.HuangGuoNative&&HuangGuoNative.exitFullscreen){ HuangGuoNative.exitFullscreen(); return true; }
          }catch(e){}
          return false;
        };
        try{ window.HGApp.syncPullRefresh(location.pathname); }catch(e){}
        (function(){
          try {
            if(!document.getElementById('hg-shell-tap-css')){
              var s=document.createElement('style');
              s.id='hg-shell-tap-css';
              s.textContent='html,body{-webkit-tap-highlight-color:transparent}';
              (document.head||document.documentElement).appendChild(s);
            }
          } catch(e) {}
        })();
        """##
    }

    /// VIP / 去广告补丁：与 APK 内 `__HG_PATCH_V1__` 字符串逐字一致。
    static let patchJS = ##"""
    (function(){
      try{
        if(window.__HG_PATCH_V1__){return;}
        window.__HG_PATCH_V1__=true;

        var of=window.fetch?window.fetch.bind(window):null;
        var OX=window.XMLHttpRequest;

        var AD_ARRAYS=['banners','icons','strip'];
        var AD_SLOT_KEYS=['splash','player_pause','detail_banner','detail_icon','detail_strip','detail_list','mine_banner','home_banner','home_icon','home_strip','pause','player_banner'];

        function stripAds(o){
          try{
            if(!o||typeof o!=='object'){return o;}
            if(Array.isArray(o)){for(var i=0;i<o.length;i++){stripAds(o[i]);}return o;}
            for(var k=0;k<AD_ARRAYS.length;k++){if(AD_ARRAYS[k] in o){o[AD_ARRAYS[k]]=[];}}
            if('slots' in o){
              if(o.slots&&typeof o.slots==='object'&&!Array.isArray(o.slots)){
                for(var s=0;s<AD_SLOT_KEYS.length;s++){o.slots[AD_SLOT_KEYS[s]]=[];}
                for(var kk in o.slots){if(Object.prototype.hasOwnProperty.call(o.slots,kk)){o.slots[kk]=[];}}
              }else{o.slots={};}
            }
            if('skip_ads' in o){o.skip_ads=true;}
            if(o.switches&&typeof o.switches==='object'){o.switches.ad_enabled=false;o.switches.vip_skip_player_ads=true;}
            if('ad_enabled' in o){o.ad_enabled=false;}
            for(var j in o){if(Object.prototype.hasOwnProperty.call(o,j)){var v=o[j];if(v&&typeof v==='object'){stripAds(v);}}}
          }catch(e){}
          return o;
        }

        function fakeVip(o){
          try{
            if(!o||typeof o!=='object'){return o;}
            if('is_vip' in o){o.is_vip=true;if('vip_expire_at' in o&&!o.vip_expire_at){o.vip_expire_at='2099-12-31T23:59:59+08:00';}}
            if('vip_expire_at' in o&&!o.vip_expire_at){o.vip_expire_at='2099-12-31T23:59:59+08:00';}
            if('need_vip' in o){o.need_vip=false;}
            if('free_episodes' in o&&typeof o.free_episodes==='number'){o.free_episodes=999999;}
            if(o.user&&typeof o.user==='object'){fakeVip(o.user);}
          }catch(e){}
          return o;
        }

        var baseCache={};
        function apiBaseOf(u){try{return u.replace(/\/app\/.*$/,'');}catch(e){return '';}}

        function resolveBase(apiBase,dramaId){
          if(baseCache[dramaId]!=null){return Promise.resolve(baseCache[dramaId]);}
          return of(apiBase+'/app/dramas/'+dramaId+'/episodes',{method:'GET'})
            .then(function(r){return r.json();})
            .then(function(eps){
              var list=(eps&&eps.list)||[];
              if(!list.length){return null;}
              var freeId=null;
              for(var i=0;i<list.length;i++){if(list[i].need_vip===false||i===0){freeId=list[i].id;break;}}
              if(freeId==null){freeId=list[0].id;}
              return of(apiBase+'/app/play/'+freeId,{method:'GET'})
                .then(function(r){return r.json();})
                .then(function(p){
                  var m=/^(https?:\/\/[^\/]+)\/storage\/(\d+)\//.exec((p&&p.play_url)||'');
                  if(!m){return null;}
                  baseCache[dramaId]={host:m[1],base:parseInt(m[2],10)};
                  return baseCache[dramaId];
                });
            })
            .catch(function(){return null;});
        }

        function unlockPlay(url,data){
          if(!data||typeof data!=='object'){return false;}
          if(data.can_play!==false){return false;}
          var ep=data.ep,dramaId=data.drama_id;
          if(!ep||!dramaId){return false;}
          var apiBase=apiBaseOf(url);
          return resolveBase(apiBase,dramaId).then(function(info){
            if(!info){return false;}
            var sid=info.base+(ep-1);
            data.can_play=true;
            data.play_url=info.host+'/storage/'+sid+'/index.m3u8';
            data.reason=null;
            data.message=null;
            data.is_vip=true;
            return true;
          }).catch(function(){return false;});
        }

        function rebuild(res,obj){
          try{
            var h={'Content-Type':'application/json; charset=utf-8'};
            return new Response(JSON.stringify(obj),{status:res.status,statusText:res.statusText,headers:h});
          }catch(e){
            return new Response(JSON.stringify(obj),{status:200,headers:{'Content-Type':'application/json; charset=utf-8'}});
          }
        }

        function isAppApi(u){return /\/api\/app\//.test(u)||/\/app\/(config|home|me|notices|dramas|play|vip|favorites|history)/.test(u);}

        if(of){
          window.fetch=function(input,init){
            var url=(typeof input==='string')?input:((input&&input.url)||'');
            return of(input,init).then(function(res){
              try{
                if(!isAppApi(url)){return res;}
                var ct=(res.headers&&res.headers.get)?(res.headers.get('content-type')||''):'';
                if(ct.indexOf('json')<0){return res;}
                return res.clone().json().then(function(data){
                  if(!data||typeof data!=='object'){return res;}
                  var p;
                  if(/\/app\/play\/\d+/.test(url)){
                    p=unlockPlay(url,data).then(function(){fakeVip(data);stripAds(data);return rebuild(res,data);});
                  }else{
                    fakeVip(data);stripAds(data);p=Promise.resolve(rebuild(res,data));
                  }
                  return p.catch(function(){return res;});
                }).catch(function(){return res;});
              }catch(e){return res;}
            });
          };
        }

        if(OX){
          var OP=OX.prototype.open,OS=OX.prototype.send;
          OX.prototype.open=function(m,u){this.__hg_url=u;return OP.apply(this,arguments);};
          OX.prototype.send=function(){
            var self=this;
            var u=self.__hg_url||'';
            if(!isAppApi(u)){return OS.apply(self,arguments);}
            var cb=function(){
              try{
                if(self.readyState!==4){return;}
                var t=self.responseText;
                if(!t){return;}
                var data=JSON.parse(t);
                if(!data||typeof data!=='object'){return;}
                var apply=function(){fakeVip(data);stripAds(data);var s=JSON.stringify(data);
                  try{Object.defineProperty(self,'responseText',{configurable:true,get:function(){return s;}});}catch(e){}
                  try{Object.defineProperty(self,'response',{configurable:true,get:function(){return s;}});}catch(e){}
                };
                if(/\/app\/play\/\d+/.test(u)){
                  unlockPlay(u,data).then(function(){apply();});
                }else{apply();}
              }catch(e){}
            };
            self.addEventListener('readystatechange',cb);
            return OS.apply(self,arguments);
          };
        }

        function killSplash(){
          try{
            var els=document.querySelectorAll('[data-hg-splash],#hg-boot-splash,[aria-label="\u5f00\u5c4f\u5e7f\u544a"]');
            for(var i=0;i<els.length;i++){var e=els[i];if(e&&e.parentNode){e.parentNode.removeChild(e);}}
          }catch(e){}
        }
        function boot(){
          killSplash();
          try{var mo=new MutationObserver(killSplash);mo.observe(document.documentElement||document,{childList:true,subtree:true});}catch(e){}
          setInterval(killSplash,250);
        }
        if(document.documentElement){boot();}
        else{document.addEventListener('DOMContentLoaded',boot);}

        window.HGApp=window.HGApp||{};
        window.HGApp.__patch='v1';
      }catch(e){}
    })();
    """##

    /// iOS 侧增补补丁（v1 保持与 APK 逐字一致，通用增强全部放在这里，互不污染）。
    ///
    /// 解决三件在真机上暴露的问题：
    ///  1. 首页两排 5×2 外链广告图标：v1 只清 `icons/banners/strip/slots` 且 `isAppApi` 路由白名单过窄，
    ///     这里做「更宽路由 + 字段清空 + 数组推广启发式 + DOM 外链栅格兜底」四层清理；
    ///  2. 播放页拖动进度条后不自动续播：WebKit 会在 seek 时把 video 置暂停，这里检测「seek 引发的 pause」
    ///     并自动 `play()` 续播（用户主动暂停在 seek 1.5s 之外，不会被误恢复）；
    ///  3. 与 v1 一样全部可重入（`__HG_PATCH_V2__` 守卫），并支持在设置页开关额外去广告。
    static func iosPatchJS(ownHosts: [String]) -> String {
        let hosts = ownHosts.map { sanitize($0) }.filter { !$0.isEmpty }
        let hostsJSON = "[" + hosts.map { "'\($0)'" }.joined(separator: ",") + "]"
        return ##"""
        (function(){
          try{
            if(window.__HG_PATCH_V2__){return;}
            window.__HG_PATCH_V2__=true;
            window.HGApp=window.HGApp||{};
            window.HGApp.__patchIos='v2.1';

            var OWN_HOSTS=\##(hostsJSON);

            function extraAds(){
              try{ return window.__HG_EXTRA_ADS__===undefined?true:!!window.__HG_EXTRA_ADS__; }catch(e){ return true; }
            }
            function playerExtra(){
              try{ return window.__HG_PLAYER_EXTRA__===undefined?true:!!window.__HG_PLAYER_EXTRA__; }catch(e){ return true; }
            }

            // ==================== 域名判定 ====================
            function own(h){
              if(!h){return true;}
              h=String(h).toLowerCase();
              if(h===String(location.host||'').toLowerCase()){return true;}
              for(var i=0;i<OWN_HOSTS.length;i++){
                var o=String(OWN_HOSTS[i]).toLowerCase();
                if(h===o){return true;}
                if(h.length>o.length&&h.slice(-(o.length+1))==='.'+o){return true;}
              }
              return false;
            }
            function hostOf(u){
              try{
                var m=/^(?:[a-z][a-z0-9+.\-]*:)?\/\/([^\/\?#]+)/i.exec(String(u||''));
                if(!m){return '';}
                return m[1].split('@').pop().split(':')[0].toLowerCase();
              }catch(e){return '';}
            }
            function isExternal(u){
              var s=String(u||'');
              if(s.indexOf('://')<0&&s.indexOf('//')!==0){
                return /^[a-z][a-z0-9+.\-]*:\/\//i.test(s)||s.indexOf('package:')===0||s.indexOf('scheme=')>=0;
              }
              var h=hostOf(s);
              return !!h&&!own(h);
            }

            // ==================== 广告字段清理 ====================
            var SAFE_KEYS=['icons','banners','strip','ads','ad_list','adlist','ad_list_v2','advertisement','advertisements',
                           'promo','promos','promotion','promotions','recommend_apps','hot_apps','download_apps','quick_apps',
                           'nav_apps','app_icons','splash_ads','float_ads','popup_ads'];
            var SUSPECT_KEYS=['links','apps','app_list','applist','nav','navs','tabs','blocks','items','list','entries','grid','quick'];
            var ICON_KEYS=['icon','logo','img','image','cover','pic','thumb','icon_url','logo_url','image_url','iconUrl','logoUrl'];
            var LINK_KEYS=['url','link','href','jump','jump_url','target','target_url','scheme','scheme_url','package','package_name',
                           'pkg','apk','download','download_url','android_url','ios_url','deeplink','deeplink_url','open_url'];

            function firstKey(o,keys){
              if(!o||typeof o!=='object'||Array.isArray(o)){return null;}
              for(var i=0;i<keys.length;i++){
                if(Object.prototype.hasOwnProperty.call(o,keys[i])){
                  var v=o[keys[i]];
                  if(v&&typeof v==='string'){return keys[i];}
                }
              }
              return null;
            }
            function looksLikePromo(o){
              try{
                if(!o||typeof o!=='object'||Array.isArray(o)){return false;}
                var ik=firstKey(o,ICON_KEYS), lk=firstKey(o,LINK_KEYS);
                if(!ik||!lk){return false;}
                return isExternal(o[lk]);
              }catch(e){return false;}
            }
            function promoRatio(list){
              if(!Array.isArray(list)||!list.length){return 0;}
              var n=0;
              for(var i=0;i<list.length;i++){ if(looksLikePromo(list[i])){n++;} }
              return n/list.length;
            }
            function cleanList(list){
              if(!Array.isArray(list)||list.length<4){return false;}
              if(promoRatio(list)>=0.5){ list.length=0; return true; }
              return false;
            }
            function deepClean(o,seen){
              try{
                if(!o||typeof o!=='object'){return o;}
                seen=seen||[];
                if(seen.indexOf(o)>=0){return o;}
                seen.push(o);
                if(Array.isArray(o)){
                  if(cleanList(o)){return o;}
                  for(var i=0;i<o.length;i++){ deepClean(o[i],seen); }
                  return o;
                }
                if(extraAds()){
                  for(var k=0;k<SAFE_KEYS.length;k++){
                    var key=SAFE_KEYS[k];
                    if(!Object.prototype.hasOwnProperty.call(o,key)){continue;}
                    var v=o[key];
                    if(Array.isArray(v)){o[key]=[];}
                    else if(v&&typeof v==='object'){o[key]={};}
                  }
                  for(var s=0;s<SUSPECT_KEYS.length;s++){
                    var sk=SUSPECT_KEYS[s];
                    if(!Object.prototype.hasOwnProperty.call(o,sk)){continue;}
                    var sv=o[sk];
                    if(Array.isArray(sv)&&cleanList(sv)){continue;}
                  }
                }
                for(var kk in o){
                  if(!Object.prototype.hasOwnProperty.call(o,kk)){continue;}
                  var vv=o[kk];
                  if(vv&&typeof vv==='object'){deepClean(vv,seen);}
                }
              }catch(e){}
              return o;
            }

            function isJsonUrl(u){
              u=String(u||'');
              if(!u){return false;}
              if(/\/api\/app\//.test(u)){return true;}
              if(/\/app\//.test(u)){return true;}
              if(/\/api\//.test(u)){return true;}
              if(/googlexml|00api-agy5u|huge1-7wnjsk|huge2-2hxu9|ihgtv-qa7pt2/.test(u)){return true;}
              return false;
            }
            function scrubJson(data){
              if(!data||typeof data!=='object'){return data;}
              deepClean(data);
              return data;
            }
            function rebuildJson(res,data){
              try{
                return new Response(JSON.stringify(data),{status:res.status,statusText:res.statusText,
                  headers:{'Content-Type':'application/json; charset=utf-8'}});
              }catch(e){
                return new Response(JSON.stringify(data),{status:200,headers:{'Content-Type':'application/json; charset=utf-8'}});
              }
            }

            if(window.fetch){
              var innerFetch=window.fetch.bind(window);
              window.fetch=function(input,init){
                var url=(typeof input==='string')?input:((input&&input.url)||'');
                return innerFetch(input,init).then(function(res){
                  try{
                    if(!extraAds()||!isJsonUrl(url)){return res;}
                    var ct=(res.headers&&res.headers.get)?(res.headers.get('content-type')||''):'';
                    if(ct.indexOf('json')<0){return res;}
                    return res.clone().json().then(function(data){
                      return rebuildJson(res,scrubJson(data));
                    }).catch(function(){return res;});
                  }catch(e){return res;}
                });
              };
            }
            if(window.XMLHttpRequest){
              var OX2=window.XMLHttpRequest;
              var OP2=OX2.prototype.open, OS2=OX2.prototype.send;
              OX2.prototype.open=function(m,u){this.__hg_url2=u;return OP2.apply(this,arguments);};
              OX2.prototype.send=function(){
                var self=this;
                var u=self.__hg_url2||'';
                if(extraAds()&&isJsonUrl(u)){
                  self.addEventListener('readystatechange',function(){
                    try{
                      if(self.readyState!==4){return;}
                      var t=self.responseText;
                      if(!t){return;}
                      var out=scrubJson(JSON.parse(t));
                      var s=JSON.stringify(out);
                      if(s===t){return;}
                      try{Object.defineProperty(self,'responseText',{configurable:true,get:function(){return s;}});}catch(e){}
                      try{Object.defineProperty(self,'response',{configurable:true,get:function(){return s;}});}catch(e){}
                    }catch(e){}
                  });
                }
                return OS2.apply(self,arguments);
              };
            }

            // ==================== 样式 ====================
            function ensureImmStyle(){
              try{
                if(document.getElementById('hg-immersive-css')){return;}
                var s=document.createElement('style');
                s.id='hg-immersive-css';
                s.textContent=
                  'html.hg-immersive,html.hg-immersive body{background:#000!important;overflow:hidden!important}'+
                  '.hg-immersive-hidden{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;height:0!important;overflow:hidden!important}'+
                  '.hg-player-box{height:100vh!important;max-height:100vh!important;margin:0!important;padding:0!important;background:#000!important}'+
                  '.hg-fill-video{width:100%!important;max-width:100%!important;height:auto!important;max-height:100%!important;object-fit:contain!important;margin:0 auto!important}'+
                  '.hg-controls-pinned{opacity:1!important;visibility:visible!important;transform:none!important;pointer-events:auto!important;transition:none!important}'+
                  '.hg-speed-shifted{margin-right:44px!important}'+
                  '.hg-strip-bottom{bottom:0!important;z-index:6!important}'+
                  '.hg-strip-hidden{display:none!important;visibility:hidden!important;height:0!important;overflow:hidden!important}';
                (document.head||document.documentElement).appendChild(s);
              }catch(e){}
            }

            // ==================== 播放器：隐藏导航 / 沉浸式 / 居中 ====================
            var fsActive=false;   // 系统全屏播放器是否在展示（webkitbegin/endfullscreen 维护）
            var playerActive=false, immActive=false;
            var hiddenNodes=[];

            function biggestVideo(){
              try{
                var vs=document.querySelectorAll('video');
                var best=null,bestArea=0;
                for(var i=0;i<vs.length;i++){
                  var r=vs[i].getBoundingClientRect();
                  var area=r.width*r.height;
                  if(area>bestArea){bestArea=area;best=vs[i];}
                }
                return best;
              }catch(e){return null;}
            }
            function containsVideo(el){
              try{
                if(!el||!el.querySelector){return false;}
                if(el.tagName==='VIDEO'){return true;}
                if(el.querySelector('video')){return true;}
                var t=(el.className&&typeof el.className==='string')?el.className:'';
                var id=el.id||'';
                if(/player|video|hg-video/i.test(t+' '+id)&&el.querySelector&&el.querySelector('video')){return true;}
                return false;
              }catch(e){return false;}
            }
            function videoVisible(){
              try{
                var v=biggestVideo();
                if(!v){return true;}
                var r=v.getBoundingClientRect();
                if(!r.width||!r.height){return false;}
                var cs=window.getComputedStyle?window.getComputedStyle(v):null;
                if(cs){
                  if(cs.display==='none'||cs.visibility==='hidden'){return false;}
                  if(parseFloat(cs.opacity||'1')===0){return false;}
                }
                var doc=document.documentElement;
                if(doc&&doc.classList&&doc.classList.contains('hg-immersive')&&r.bottom<0){return false;}
                return true;
              }catch(e){return true;}
            }
            function playerBox(v){
              try{
                var vw=window.innerWidth||0;
                var vh=v?v.getBoundingClientRect().height:0;
                var node=v?v.parentNode:null;
                var fallback=null,guard=0;
                while(node&&node!==document.body&&guard<6){
                  var r=node.getBoundingClientRect();
                  if(r.width>=vw*0.75){
                    if(!fallback){fallback=node;}                       // 最近的一个满宽祖先作为兜底
                    if(r.height>=vh+8){return node;}                    // 能装下视频 → 就用它（不再往外套）
                  }
                  node=node.parentNode; guard++;
                }
                return fallback||(v?v.parentNode:null);
              }catch(e){return v?v.parentNode:null;}
            }
            function textOf(el){
              try{
                var t=(el.innerText||el.textContent||'');
                return t.length>400?'':t;
              }catch(e){return '';}
            }
            function isBottomDock(el,vh){
              // 只认「矮、宽、贴底、含 ≥3 个主 tab 关键词、且不含 video」的节点，避免误伤整页容器
              try{
                if(!el||!el.getBoundingClientRect){return false;}
                if(el===document.body||el===document.documentElement){return false;}
                if(containsVideo(el)){return false;}
                var r=el.getBoundingClientRect();
                if(r.height<=0||r.width<=0){return false;}
                if(r.height>vh*0.22){return false;}
                if(r.width<window.innerWidth*0.7){return false;}
                if(r.bottom<vh*0.75){return false;}
                var t=textOf(el);
                if(!t){return false;}
                var keys=['首页','分类','搜索','我的','发现','会员','追剧'];
                var hits=0;
                for(var i=0;i<keys.length;i++){ if(t.indexOf(keys[i])>=0){hits++;} }
                return hits>=3;
              }catch(e){return false;}
            }
            function isTopHeader(el,vh){
              // 只认「矮、贴顶、含搜索框/搜索字样、且不含 video」的节点
              try{
                if(!el||!el.getBoundingClientRect){return false;}
                if(el===document.body||el===document.documentElement){return false;}
                if(containsVideo(el)){return false;}
                var r=el.getBoundingClientRect();
                if(r.height<=0||r.width<=0){return false;}
                if(r.height>vh*0.20){return false;}
                if(r.top>vh*0.16){return false;}
                if(el.querySelector&&el.querySelector('input[type=search],input[type=text],input:not([type])')){return true;}
                var t=textOf(el);
                return !!t&&/搜索|搜/.test(t);
              }catch(e){return false;}
            }
            function walkBounded(root,cb,budget,depth){
              try{
                var kids=(root&&root.children)||[];
                for(var i=0;i<kids.length;i++){
                  if(budget.n<=0){return;}
                  var el=kids[i];
                  budget.n--;
                  cb(el,depth);
                  if(depth<4&&budget.n>0){ walkBounded(el,cb,budget,depth+1); }
                }
              }catch(e){}
            }
            function markChrome(hide){
              try{
                ensureImmStyle();
                var vh=window.innerHeight||0;
                if(!hide){
                  for(var i=0;i<hiddenNodes.length;i++){
                    var node=hiddenNodes[i];
                    if(node&&node.classList){ node.classList.remove('hg-immersive-hidden'); }
                  }
                  hiddenNodes=[];
                  return;
                }
                var found=[];
                walkBounded(document.body,function(el){
                  if(isBottomDock(el,vh)||isTopHeader(el,vh)){
                    if(found.indexOf(el)<0){found.push(el);}
                  }
                },{n:700},1);
                for(var j=0;j<found.length;j++){
                  var target=found[j];
                  if(target.classList&&!target.classList.contains('hg-immersive-hidden')){
                    target.classList.add('hg-immersive-hidden');
                    hiddenNodes.push(target);
                  }
                }
                // 安全网：隐藏导航后如果视频看不见了，立刻整体回滚，宁可留着导航也不能黑屏
                if(found.length&&!videoVisible()){
                  for(var k=0;k<hiddenNodes.length;k++){
                    var back=hiddenNodes[k];
                    if(back&&back.classList){ back.classList.remove('hg-immersive-hidden'); }
                  }
                  hiddenNodes=[];
                  try{ window.HGApp.__lastRollback='chrome-hidden-video'; }catch(e){}
                }
              }catch(e){}
            }
            function nudgeVideo(v,dy){
              try{
                if(typeof v.__hgBaseTransform==='undefined'){ v.__hgBaseTransform=v.style.transform||''; }
                var t=(dy===0)?v.__hgBaseTransform:(v.__hgBaseTransform+' translateY('+Math.round(dy)+'px)');
                v.style.transform=t;
              }catch(e){}
            }
            function centerVideo(){
              try{
                var v=biggestVideo();
                if(!v){return 'novideo';}
                var box=playerBox(v)||v.parentNode;
                if(!box){return 'nobox';}
                // 关键：先把「我们自己施加过的位移」扣掉再测量，否则每次重算都会看到自己造成的变化 → 上下晃动
                var applied=(typeof v.__hgNudge==='number')?v.__hgNudge:0;
                var vr=v.getBoundingClientRect();
                var baseTop=vr.top-applied;
                var baseCenter=baseTop+vr.height/2;
                var br=box.getBoundingClientRect();
                var vh=window.innerHeight||0;
                var targetY=immActive?(br.top+br.height/2):(vh/2);
                var dy=targetY-baseCenter;
                if(!isFinite(dy)){dy=0;}
                var limit=Math.max(0,vh*0.25);
                dy=Math.max(-limit,Math.min(limit,dy));
                var slackUp=Math.max(0,baseTop-br.top);
                var slackDown=Math.max(0,(br.top+br.height)-(baseTop+vr.height));
                dy=(dy<0)?Math.max(dy,-slackUp):Math.min(dy,slackDown);
                if(Math.abs(dy-applied)<3){ return 'keep='+Math.round(applied); }
                v.__hgNudge=dy;
                nudgeVideo(v,dy);
                if(!videoVisible()){ v.__hgNudge=0; nudgeVideo(v,0); return 'rollback'; }
                return 'dy='+Math.round(dy);
              }catch(e){return 'err';}
            }
            function boxIsFixed(box){
              try{
                var cs=window.getComputedStyle?window.getComputedStyle(box):null;
                var pos=cs?cs.position:'';
                return pos==='fixed'||pos==='absolute'||pos==='sticky';
              }catch(e){return false;}
            }
            function applyImmersive(on){
              try{
                ensureImmStyle();
                var v=biggestVideo();
                var box=v?playerBox(v):null;
                if(on){
                  try{document.documentElement.classList.add('hg-immersive');}catch(e){}
                  // 只在「文档流内」的容器上撑满高度；原本 fixed/absolute 的全屏播放层保持原样，
                  // 否则会被强改定位而挪出视口（这正是之前黑屏只剩声音的原因）。
                  if(box&&box.classList&&!boxIsFixed(box)){ box.classList.add('hg-player-box'); }
                  if(v&&v.classList){ v.classList.add('hg-fill-video'); }
                  markChrome(true);
                  if(!videoVisible()){
                    // 回滚：撤掉所有改动，保留可播放画面
                    try{document.documentElement.classList.remove('hg-immersive');}catch(e){}
                    if(box&&box.classList){ box.classList.remove('hg-player-box'); }
                    if(v){
                      v.classList.remove('hg-fill-video');
                      if(typeof v.__hgBaseTransform!=='undefined'){ v.style.transform=v.__hgBaseTransform; }
                    }
                    markChrome(false);
                    immActive=false;
                    try{ window.HGApp.__lastRollback='immersive-hidden-video'; }catch(e){}
                    return;
                  }
                }else{
                  try{document.documentElement.classList.remove('hg-immersive');}catch(e){}
                  var boxes=document.querySelectorAll('.hg-player-box');
                  for(var i=0;i<boxes.length;i++){ boxes[i].classList.remove('hg-player-box'); }
                  var fills=document.querySelectorAll('.hg-fill-video');
                  for(var j=0;j<fills.length;j++){ fills[j].classList.remove('hg-fill-video'); }
                  if(v){
                    v.style.maxWidth='';v.style.maxHeight='';v.style.width='';v.style.height='';v.style.objectFit='';
                    if(typeof v.__hgBaseTransform!=='undefined'){ v.style.transform=v.__hgBaseTransform; }
                  }
                  if(playerActive){ markChrome(true); } else { markChrome(false); }
                }
                immActive=on;
              }catch(e){}
            }


            // ==================== 播放器调优（竖屏）：控件常显 / 选集条下移 / 满宽渲染 / 稳定居中 ====================
            var pinnedRow=null, pinnedStrip=null, lastLayoutSig='', speedEl=null, postSeq2=0;

            function playerTuning(){
              try{ return window.__HG_PLAYER_TUNE__===undefined?true:!!window.__HG_PLAYER_TUNE__; }catch(e){ return true; }
            }
            function postNative(method,args){
              try{
                postSeq2++;
                window.webkit.messageHandlers.HuangGuoNative.postMessage(JSON.stringify({id:'layout'+postSeq2,method:method,args:args||[]}));
              }catch(e){}
            }
            function playerSig(){
              try{
                var v=biggestVideo();
                if(!v){return 'novideo';}
                var box=playerBox(v)||v.parentNode;
                if(!box){return 'nobox';}
                var br=box.getBoundingClientRect(), vr=v.getBoundingClientRect();
                return [playerActive?1:0,immActive?1:0,window.innerWidth,window.innerHeight,
                        Math.round(br.top),Math.round(br.height),Math.round(vr.width),Math.round(vr.height),playerTuning()?1:0].join(',');
              }catch(e){return 'sigerr';}
            }
            function findControlsRow(box){
              try{
                var vh=window.innerHeight||0;
                if(!box||!box.querySelectorAll){return null;}
                var nodes=box.querySelectorAll('div,section,footer,ul');
                var best=null,bestH=1e9;
                for(var i=0;i<nodes.length;i++){
                  var el=nodes[i];
                  var r=el.getBoundingClientRect();
                  if(!r.height||r.height>vh*0.22){continue;}
                  if(r.top<vh*0.45){continue;}
                  var t=(el.innerText||el.textContent||'');
                  if(t.length>200||!/\d{1,2}:\d{2}/.test(t)){continue;}
                  if(r.height<bestH){bestH=r.height;best=el;}
                }
                return best;
              }catch(e){return null;}
            }
            function findSpeedEl(box){
              try{
                if(!box||!box.querySelectorAll){return null;}
                var nodes=box.querySelectorAll('span,div,p,button,a');
                for(var i=0;i<nodes.length;i++){
                  var el=nodes[i];
                  var t=(el.textContent||'').trim();
                  if(!/^[0-9](\.[0-9])?x$/i.test(t)){continue;}
                  var r=el.getBoundingClientRect();
                  if(r.width>0&&r.height>0){return el;}
                }
              }catch(e){}
              return null;
            }
            function findStripEl(box){
              try{
                var vh=window.innerHeight||0, vw=window.innerWidth||0;
                var scopes=[];
                if(box&&box.parentNode){scopes.push(box.parentNode);}
                if(document.body){scopes.push(document.body);}
                for(var s=0;s<scopes.length;s++){
                  var nodes=(scopes[s]&&scopes[s].querySelectorAll)?scopes[s].querySelectorAll('div,section,footer'):[];
                  var best=null,bestH=1e9;
                  for(var i=0;i<nodes.length;i++){
                    var el=nodes[i];
                    var r=el.getBoundingClientRect();
                    if(!r.height||r.height>vh*0.14){continue;}
                    if(r.width<vw*0.6){continue;}
                    var t=(el.innerText||el.textContent||'');
                    if(t.indexOf('选集')<0||t.length>140){continue;}
                    if(r.height<bestH){bestH=r.height;best=el;}
                  }
                  if(best){return best;}
                }
              }catch(e){}
              return null;
            }
            function pinControls(){
              try{
                var v=biggestVideo();
                if(!v){return null;}
                var row=findControlsRowDoc();
                if(!row){
                  var box=playerBox(v)||v.parentNode;
                  row=findControlsRow(box);
                }
                if(row&&row.classList){
                  if(!row.classList.contains('hg-controls-pinned')){ row.classList.add('hg-controls-pinned'); }
                  pinnedRow=row;
                }
                return row;
              }catch(e){return null;}
            }
            function reserveStripSpace(row){
              try{
                var v=biggestVideo();
                if(!v){return 0;}
                var box=playerBox(v)||v.parentNode;
                var strip=findStripEl(box);
                if(!strip){return 0;}
                if(strip.classList&&!strip.classList.contains('hg-strip-bottom')){ strip.classList.add('hg-strip-bottom'); }
                pinnedStrip=strip;
                var sr=strip.getBoundingClientRect();
                if(!sr.height||sr.height<4){return 0;}
                var pad=Math.round(sr.height)+4;
                if(box&&box.style&&box.__hgStripPad!==pad){
                  var cs=window.getComputedStyle?window.getComputedStyle(box):null;
                  var borderBox=!cs||cs.boxSizing==='border-box';
                  var br=box.getBoundingClientRect();
                  if(borderBox||br.height<=pad){
                    box.style.paddingBottom=pad+'px';
                  }else{
                    box.style.height=Math.round(br.height-pad)+'px';
                    box.style.paddingBottom=pad+'px';
                  }
                  box.__hgStripPad=pad;
                }
                return pad;
              }catch(e){return 0;}
            }
            function shiftSpeedAndReport(){
              try{
                var v=biggestVideo();
                if(!v){return;}
                var el=findSpeedElDoc();
                if(!el){
                  var box=playerBox(v)||v.parentNode;
                  el=findSpeedEl(box);
                }
                if(!el){return;}
                speedEl=el;
                if(!el.classList.contains('hg-speed-shifted')){ el.classList.add('hg-speed-shifted'); }
                var r=el.getBoundingClientRect();
                postNative('playerControls',[Math.round(r.left),Math.round(r.top),Math.round(r.width),Math.round(r.height),Math.round(window.innerWidth)]);
              }catch(e){}
            }
            function keepPins(){
              // 轻量维持：只补类，不做任何测量，避免播放中强制回流
              try{
                if(pinnedRow&&pinnedRow.classList&&!pinnedRow.classList.contains('hg-controls-pinned')){
                  pinnedRow.classList.add('hg-controls-pinned');
                }
                if(pinnedStrip&&pinnedStrip.classList&&!pinnedStrip.classList.contains('hg-strip-bottom')){
                  pinnedStrip.classList.add('hg-strip-bottom');
                }
                if(speedEl&&speedEl.classList&&!speedEl.classList.contains('hg-speed-shifted')){
                  speedEl.classList.add('hg-speed-shifted');
                }
              }catch(e){}
            }
            function layoutPlayer(force){
              if(!playerActive){return 'not-player';}
              try{
                var sig=playerSig();
                if(!force&&sig===lastLayoutSig){ keepPins(); return 'keep'; }
                lastLayoutSig=sig;
                if(!playerTuning()){ return 'tuning-off'; }
                var v=biggestVideo();
                if(v&&v.classList&&!immActive&&!v.classList.contains('hg-fill-video')){
                  v.classList.add('hg-fill-video');   // 竖屏也按满宽渲染 → 更清晰
                }
                var row=pinControls();
                applyStripPolicy();
                shiftSpeedAndReport();
                centerVideo();
                return 'layout';
              }catch(e){return 'err';}
            }
            window.HGApp.layoutPlayer=layoutPlayer;
            window.HGApp.setPlayerTuning=function(on){ window.__HG_PLAYER_TUNE__=!!on; lastLayoutSig=''; return layoutPlayer(true); };
            // ---- v2.4：全文档范围定位速度键 / 隐藏选集条 / 视频比例与全屏状态上报 ----
            function leafByText(pattern, limit){
              try{
                var nodes=document.querySelectorAll('span,div,p,button,a,i');
                var seen=0;
                for(var i=0;i<nodes.length;i++){
                  var el=nodes[i];
                  if(el.children&&el.children.length>0){continue;}      // 只看叶子节点，避免 textContent 大范围拼接
                  seen++;
                  if(seen>limit){break;}
                  var t=(el.textContent||'').trim();
                  if(pattern.test(t)){
                    var r=el.getBoundingClientRect();
                    if(r.width>0&&r.height>0){return el;}
                  }
                }
              }catch(e){}
              return null;
            }
            function findSpeedElDoc(){
              return leafByText(/^[0-9](\.[0-9])?x$/i, 600) || leafByText(/^(倍速|全屏)$/, 600);
            }
            function findControlsRowDoc(){
              try{
                var vh=window.innerHeight||0;
                var nodes=document.querySelectorAll('div,section,footer,ul');
                var best=null,bestH=1e9,seen=0;
                for(var i=0;i<nodes.length;i++){
                  var el=nodes[i];
                  seen++;
                  if(seen>500){break;}
                  if(el.children&&el.children.length>12){continue;}
                  var t=(el.innerText||el.textContent||'');
                  if(t.length>200||!/\d{1,2}:\d{2}/.test(t)){continue;}
                  var r=el.getBoundingClientRect();
                  if(!r.height||r.height>vh*0.24){continue;}
                  if(r.top<vh*0.35){continue;}
                  if(r.height<bestH){bestH=r.height;best=el;}
                }
                return best;
              }catch(e){return null;}
            }
            function findStripElDoc(){
              try{
                var vh=window.innerHeight||0, vw=window.innerWidth||0;
                var nodes=document.querySelectorAll('div,section,footer');
                var best=null,bestH=1e9,seen=0;
                for(var i=0;i<nodes.length;i++){
                  var el=nodes[i];
                  seen++;
                  if(seen>600){break;}
                  var r=el.getBoundingClientRect();
                  if(!r.height||r.height>vh*0.14){continue;}
                  if(r.width<vw*0.6){continue;}
                  var t=(el.innerText||el.textContent||'');
                  if(t.indexOf('选集')<0||t.length>140){continue;}
                  if(r.height<bestH){bestH=r.height;best=el;}
                }
                return best;
              }catch(e){return null;}
            }
            function applyStripPolicy(){
              try{
                var v=biggestVideo();
                if(!v){return 'novideo';}
                var strip=pinnedStrip||findStripElDoc();
                if(!strip){return 'nostrip';}
                pinnedStrip=strip;
                var hide=(window.__HG_STRIP_HIDDEN__===undefined)?true:!!window.__HG_STRIP_HIDDEN__;
                if(hide){
                  if(!strip.classList.contains('hg-strip-hidden')){ strip.classList.add('hg-strip-hidden'); }
                  strip.classList.remove('hg-strip-bottom');
                  return 'hidden';
                }
                strip.classList.remove('hg-strip-hidden');
                if(!strip.classList.contains('hg-strip-bottom')){ strip.classList.add('hg-strip-bottom'); }
                var sr=strip.getBoundingClientRect();
                var box=playerBox(v)||v.parentNode;
                if(box&&box.style&&sr.height>4){
                  var pad=Math.round(sr.height)+4;
                  if(box.__hgStripPad!==pad){ box.style.paddingBottom=pad+'px'; box.__hgStripPad=pad; }
                }
                return 'visible';
              }catch(e){return 'err';}
            }
            function videoInfo(){
              try{
                var v=biggestVideo();
                if(!v){return JSON.stringify({w:0,h:0});}
                var w=v.videoWidth||0, h=v.videoHeight||0;
                if(!w||!h){
                  var r=v.getBoundingClientRect();
                  return JSON.stringify({w:Math.round(r.width),h:Math.round(r.height),fallback:true});
                }
                return JSON.stringify({w:w,h:h});
              }catch(e){return JSON.stringify({w:0,h:0});}
            }
            function reportFullscreen(active){
              try{
                var info=JSON.parse(videoInfo());
                postNative('fullscreenState',[active?1:0,info.w||0,info.h||0]);
              }catch(e){}
            }
            window.HGApp.videoInfo=videoInfo;
            window.HGApp.setStripHidden=function(on){ window.__HG_STRIP_HIDDEN__=!!on; return applyStripPolicy(); };
            window.HGApp.reportFullscreenNow=function(){ reportFullscreen(!!fsActive); return true; };

            document.addEventListener('webkitbeginfullscreen',function(){ fsActive=true; reportFullscreen(true); },true);
            document.addEventListener('webkitendfullscreen',function(){ fsActive=false; reportFullscreen(false); },true);
            function playerDiag(){
              try{
                var vs=document.querySelectorAll('video');
                var v=biggestVideo();
                var r=v?v.getBoundingClientRect():null;
                return JSON.stringify({
                  videos:vs.length,
                  visible:videoVisible(),
                  rect:r?{w:Math.round(r.width),h:Math.round(r.height),top:Math.round(r.top)}:null,
                  hidden:hiddenNodes.length,
                  rollback:(window.HGApp&&window.HGApp.__lastRollback)||'',
                  player:playerActive,
                  immersive:immActive,
                  tuning:playerTuning(),
                  pinned:!!pinnedRow,
                  strip:!!pinnedStrip,
                  stripHidden:(pinnedStrip&&pinnedStrip.classList)?pinnedStrip.classList.contains('hg-strip-hidden'):null,
                  fullscreen:fsActive,
                  nudge:(function(){try{var v=biggestVideo();return v&&typeof v.__hgNudge==='number'?Math.round(v.__hgNudge):0;}catch(e){return 0;}})()
                });
              }catch(e){ return '{}'; }
            }
            window.HGApp.playerDiag=playerDiag;

            function fixVideoLayout(){
              try{
                var v=biggestVideo();
                if(!v){return;}
                var vw=window.innerWidth||0;
                if(!vw){return;}
                var r=v.getBoundingClientRect();
                if(!r.width){return;}
                var overflow=r.width>vw+1;
                var offCenter=Math.abs((r.left+r.width/2)-vw/2)>8;
                if(!overflow&&!offCenter){return;}
                if(v.classList){ v.classList.add('hg-fill-video'); }
                nudgeVideo(v,0);
              }catch(e){}
            }

            window.HGApp.setPlayerMode=function(on){
              playerActive=!!on;
              try{
                if(playerActive&&playerExtra()){ ensureImmStyle(); markChrome(true); }
                else {
                  immActive=false;
                  applyImmersive(false);
                  markChrome(false);
                }
              }catch(e){}
              scheduleSweep(true);
              return true;
            };
            window.HGApp.setImmersive=function(on){
              var target=!!on&&playerExtra();
              try{ applyImmersive(target); }catch(e){}
              if(!target&&playerActive){ try{ markChrome(true); }catch(e){} }
              scheduleSweep(true);
              return true;
            };
            window.HGApp.centerVideo=centerVideo;
            window.HGApp.fixVideoLayout=fixVideoLayout;

            // ==================== DOM 广告清理 ====================
            var gid=0;
            function nodeKey(n){
              try{
                if(!n.__hgKey){ gid++; n.__hgKey='g'+gid; }
                return n.__hgKey;
              }catch(e){return 'x';}
            }
            function killExternalIconGrid(){
              try{
                var anchors=document.querySelectorAll('a[href]');
                var groups={};
                for(var i=0;i<anchors.length;i++){
                  var a=anchors[i];
                  var href=a.getAttribute('href')||'';
                  if(!isExternal(href)){continue;}
                  if(!a.querySelector('img')){continue;}
                  var p=a.parentNode;
                  if(!p){continue;}
                  var k=nodeKey(p);
                  (groups[k]=groups[k]||[]).push(a);
                }
                for(var kk in groups){
                  if(!Object.prototype.hasOwnProperty.call(groups,kk)){continue;}
                  var list=groups[kk];
                  if(list.length<4){continue;}
                  for(var j=0;j<list.length;j++){
                    var el=list[j];
                    if(el&&el.parentNode){ el.parentNode.removeChild(el); }
                  }
                }
              }catch(e){}
            }
            function killAdMarkers(){
              try{
                var els=document.querySelectorAll('[data-ad],[data-ads],[data-advert],[class*="ad-banner"],[class*="ad_banner"],[class*="advert"]');
                for(var i=0;i<els.length;i++){
                  var el=els[i];
                  if(el&&el.parentNode){ el.parentNode.removeChild(el); }
                }
              }catch(e){}
            }

            // ==================== 播放：seek 续播（最多重试 2 次，避免拖进度时抖动） ====================
            var lastPauseAt=0, seekingAt=0;
            function isVideo(e){
              try{ return e&&e.target&&e.target.tagName==='VIDEO'?e.target:null; }catch(e2){return null;}
            }
            function tryPlay(v,left){
              try{
                if(!v.paused){return;}
                var p=v.play();
                if(p&&p.catch){ p.catch(function(){ if(left>0){ setTimeout(function(){ tryPlay(v,left-1); },300); } }); }
              }catch(e){}
            }
            document.addEventListener('pause',function(e){
              var v=isVideo(e);
              if(v){ lastPauseAt=Date.now(); }
            },true);
            document.addEventListener('seeking',function(e){
              if(isVideo(e)){ seekingAt=Date.now(); }
            },true);
            document.addEventListener('seeked',function(e){
              var v=isVideo(e);
              if(!v){return;}
              var justPaused=(Date.now()-lastPauseAt)<1500;
              if(justPaused||!v.paused){ tryPlay(v,2); }
            },true);
            document.addEventListener('waiting',function(e){
              var v=isVideo(e);
              if(!v){return;}
              if((Date.now()-seekingAt)<4000){ setTimeout(function(){ tryPlay(v,1); },300); }
            },true);

            // ==================== 清扫节流（播放页 DOM 每 ~100ms 更新，必须防抖，否则拖进度会卡） ====================
            var sweepPending=false,lastSweep=0;
            var MIN_INTERVAL=1600;
            function runSweep(){
              try{
                // 有视频正在播放时不做任何 DOM 扫描/改动，避免拖进度时被强制回流打断（卡顿根因之一）
                var vs=document.querySelectorAll('video');
                var playing=false;
                for(var i=0;i<vs.length;i++){ if(vs[i]&&!vs[i].paused){playing=true;break;} }
                if(extraAds()&&!playing){
                  killExternalIconGrid();
                  killAdMarkers();
                }
                if(playerActive){
                  keepPins();
                  if(!playing){ layoutPlayer(false); }   // 正在播放时不做任何测量，避免拖进度被打断
                }else{
                  fixVideoLayout();
                }
              }catch(e){}
            }
            function scheduleSweep(immediate){
              try{
                if(sweepPending){return;}
                sweepPending=true;
                var delay=immediate?0:220;
                setTimeout(function(){
                  sweepPending=false;
                  var now=Date.now();
                  if(now-lastSweep<MIN_INTERVAL && !immediate){ return; }
                  lastSweep=now;
                  runSweep();
                },delay);
              }catch(e){ sweepPending=false; }
            }
            window.HGApp.sweepAds=scheduleSweep;

            try{
              window.addEventListener('resize',function(){
                scheduleSweep(true);
                if(playerActive){ setTimeout(centerVideo,80); setTimeout(centerVideo,320); }
              });
              window.addEventListener('orientationchange',function(){
                if(playerActive){ setTimeout(centerVideo,120); setTimeout(centerVideo,420); }
              });
            }catch(e){}

            function boot2(){
              scheduleSweep(true);
              try{
                var mo=new MutationObserver(function(){ scheduleSweep(false); });
                mo.observe(document.documentElement||document,{childList:true,subtree:true});
              }catch(e){}
              setInterval(function(){ scheduleSweep(false); },2600);
            }
            if(document.documentElement){boot2();}
            else{document.addEventListener('DOMContentLoaded',boot2);}
          }catch(e){}
        })();
        """##
    }

    /// 额外去广告开关（设置页可实时切换，无需重装）。
    static func extraAdsFlagJS(_ enabled: Bool) -> String {
        ##"""
        window.__HG_EXTRA_ADS__=\##(enabled ? "true" : "false");
        """##
    }

    /// 播放器调优开关（控件常显 / 选集条下移 / 速度键让位 / 满宽渲染），设置页可实时切换。
    static func playerTuneFlagJS(_ enabled: Bool) -> String {
        ##"""
        window.__HG_PLAYER_TUNE__=\##(enabled ? "true" : "false");
        """##
    }

    /// 播放页增强开关（隐藏导航/沉浸式/居中），设置页可实时切换。
    static func playerExtraFlagJS(_ enabled: Bool) -> String {
        ##"""
        window.__HG_PLAYER_EXTRA__=\##(enabled ? "true" : "false");
        """##
    }
    /// 让页面上最大的 `<video>` 进原生全屏（iOS 上 `screen.orientation.lock()` 不可用，
    /// 「横屏」由外壳通过 `webkitEnterFullscreen` + 几何更新实现）。
    static let enterNativeFullscreenJS = ##"""
    (function(){
      try{
        var vs=document.querySelectorAll('video');
        var best=null,bestW=0;
        for(var i=0;i<vs.length;i++){
          var r=vs[i].getBoundingClientRect();
          if(r.width>bestW){bestW=r.width;best=vs[i];}
        }
        if(!best){return 'novideo';}
        try{ if(best.webkitEnterFullscreen){ best.webkitEnterFullscreen(); return 'native'; } }catch(e){}
        try{ if(best.requestFullscreen){ best.requestFullscreen(); return 'std'; } }catch(e){}
      }catch(e){}
      return 'none';
    })();
    """##

    /// 退出全屏（原生全屏优先，其次 Fullscreen API）。
    static let exitNativeFullscreenJS = ##"""
    (function(){
      try{
        var v=document.querySelector('video');
        if(v&&v.webkitDisplayingFullscreen&&v.webkitExitFullscreen){ v.webkitExitFullscreen(); return 'native'; }
        if(document.fullscreenElement&&document.exitFullscreen){ document.exitFullscreen(); return 'std'; }
      }catch(e){}
      return 'none';
    })();
    """##

    /// 旋转后通知 H5 重新排版（否则播放器仍按旧视口尺寸居中 → 看起来偏了）。
    static let resizeDispatchJS = ##"""
    (function(){
      try{ window.dispatchEvent(new Event('resize')); }catch(e){}
      try{ window.dispatchEvent(new Event('orientationchange')); }catch(e){}
    })();
    """##

    /// 注入用的自有域名清单：正式种子 + API 基址（+ 调试种子）。与 `ShellModel.trustedHosts` 同源但可静态计算，
    /// 以便在 `atDocumentStart` 就装好补丁（避免首页首个数据请求抢在注入之前）。
    static func staticOwnHosts(includeDebugSeeds: Bool) -> [String] {
        var hosts = Set<String>()
        func add(_ value: String) {
            guard let host = URL(string: value)?.host?.lowercased(), !host.isEmpty else { return }
            hosts.insert(host)
        }
        AppConfig.releaseSeeds.forEach(add)
        add(AppConfig.apiSeed)
        add(AppConfig.apiSeedBackup)
        if includeDebugSeeds {
            AppConfig.debugSeedHosts.forEach { hosts.insert($0.lowercased()) }
        }
        return Array(hosts).sorted()
    }

    /// 返回键协商脚本：H5 优先处理，未处理则由外壳决定 goBack/finish。
    static let handleBackJS = ##"""
    (function(){
      try {
        if (window.__HG_HANDLE_BACK__ && typeof window.__HG_HANDLE_BACK__ === 'function') {
          if (window.__HG_HANDLE_BACK__()) return 'handled';
        }
        if (window.history && window.history.length > 1) {
          /* 交给 WebView canGoBack */
        }
      } catch (e) {}
      return 'none';
    })();
    """##

    /// 更新结果回传：与 Android `notifyUpdateResult` 生成的脚本一致。
    static func updateResultJS(ok: Bool, message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return ##"""
        try{
          window.dispatchEvent(new CustomEvent('hg-app-update-result',{
            detail:{ok:\##(ok ? "true" : "false"),message:'\##(escaped)'}
          }));
        }catch(e){}
        """##
    }

    /// 把促销绑定 token 推给 H5（Android 端为同步取值，iOS 用缓存 + 事件补齐）。
    static func promoTokenJS(_ token: String) -> String {
        let safe = sanitize(token)
        return ##"""
        window.__HG_BRIDGE_CACHE__=window.__HG_BRIDGE_CACHE__||{};
        window.__HG_BRIDGE_CACHE__.promoBindToken='\##(safe)';
        try{ window.dispatchEvent(new CustomEvent('hg-promo-bind',{detail:{bind_token:'\##(safe)'}})); }catch(e){}
        """##
    }

    /// 同步缓存（apiBase / promoAgentId）推送。
    static func bridgeCacheJS(apiBase: String, promoAgentId: String) -> String {
        ##"""
        window.__HG_BRIDGE_CACHE__=window.__HG_BRIDGE_CACHE__||{};
        window.__HG_BRIDGE_CACHE__.apiBase='\##(sanitize(apiBase))';
        window.__HG_BRIDGE_CACHE__.promoAgentId='\##(sanitize(promoAgentId))';
        """##
    }
}
