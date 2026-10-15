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
