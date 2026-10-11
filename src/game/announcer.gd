class_name Announcer
## Arena announcer voice ("FIRST BLOOD!", "RAMPAGE!", "VICTORY!") using the browser's built-in
## speech synthesis: no audio assets, no server. Web only; silent on desktop and in tests.
##
## Priority queue (lives on the JS side, so it can react to the utterance's end event):
##   - idle: the line plays at once.
##   - busy: a line of HIGHER priority than the one playing cuts it off (and drops waiting
##     lines below it); LOW lines are dropped; others wait (max 3, best first, FIFO per
##     priority) and expire after 3 s unless CRITICAL. Lines never overlap.
## The best English (preferably British, male, "natural") voice is picked once and cached on
## `window.__flVoiceName`; Chrome loads voices async, so it re-picks on `voiceschanged`.

const LOW := 0         # countdown ticks: dropped when anything is playing
const NORMAL := 1      # headshot, humiliation, lead changes, frags/time remaining
const HIGH := 2        # first blood, multi kills, sprees, redeemer
const CRITICAL := 3    # pre-match 3-2-1 + FIGHT, end of match

const PITCH := 0.55    # deep, dramatic UT delivery
const RATE := 1.0

## Every requested line, on every platform (tests read it). Capped so a long session can't grow it.
static var log: Array = []
static var _installed := false

const _JS := """(function(){
if(window.__flSay)return;
var S=null;try{S=window.speechSynthesis||null;}catch(e){}
var st={cur:-1,u:null,until:0,q:[],voice:null,score:-99};
function score(v){var n=v.name||'',l=(v.lang||'').toLowerCase().replace('_','-');
if(l.indexOf('en')!==0)return -99;var s=l.indexOf('en-gb')===0?3:(l.indexOf('en-us')===0?2:1);
if(/natural|neural|online|premium|enhanced/i.test(n))s+=3;
if(/google uk english male/i.test(n))s+=9;
if(/\\b(male|man|guy|ryan|davis|christopher|eric|roger|thomas|brian|andrew|daniel|george|david|mark|james|arthur|oliver|alex|fred|tom|aaron|evan|rishi)\\b/i.test(n))s+=5;
if(/female|woman|zira|susan|hazel|libby|sonia|maisie|aria|jenny|michelle|samantha|karen|victoria|fiona|moira|tessa|serena|kate|ava|allison|emma|nicky/i.test(n))s-=6;
return s;}
function pick(){try{if(!S)return;var vs=S.getVoices()||[];for(var i=0;i<vs.length;i++){var s=score(vs[i]);
if(s>st.score){st.score=s;st.voice=vs[i];}}if(st.voice)window.__flVoiceName=st.voice.name;}catch(e){}}
function busy(){if(!st.u)return false;if(Date.now()>st.until){st.u=null;st.cur=-1;return false;}return true;}
function next(){var now=Date.now();while(st.q.length){var it=st.q.shift();if(it.pr>=3||now-it.at<3000){speak(it);return;}}}
function speak(it){try{var u=new SpeechSynthesisUtterance(it.t);if(st.voice){u.voice=st.voice;u.lang=st.voice.lang;}else u.lang='en-GB';
u.pitch=it.p;u.rate=it.r;u.volume=it.v;st.u=u;st.cur=it.pr;st.until=Date.now()+1200+it.t.length*120/it.r;
u.onend=u.onerror=function(){if(st.u!==u)return;st.u=null;st.cur=-1;next();};
if(S.paused)S.resume();S.speak(u);}catch(e){st.u=null;st.cur=-1;}}
function req(it){try{
if(!st.voice){pick();if(!st.voice&&!it.retry){it.retry=1;setTimeout(function(){req(it);},250);return;}}
if(!busy()){if(S.speaking||S.pending)S.cancel();speak(it);return;}
if(it.pr>st.cur){var keep=[];for(var i=0;i<st.q.length;i++)if(st.q[i].pr>=it.pr)keep.push(st.q[i]);st.q=keep;
st.u=null;st.cur=-1;S.cancel();speak(it);return;}
if(it.pr<=0)return;
var j=st.q.length;while(j>0&&st.q[j-1].pr<it.pr)j--;st.q.splice(j,0,it);if(st.q.length>3)st.q.pop();
}catch(e){}}
window.__flSay=function(t,pr,p,r,v){if(!S||typeof SpeechSynthesisUtterance==='undefined')return;
req({t:t,pr:pr,p:p,r:r,v:v,at:Date.now()});};
if(S){pick();try{S.addEventListener('voiceschanged',pick);}catch(e){try{S.onvoiceschanged=pick;}catch(e2){}}}
})();"""


static func say(text: String, prio := NORMAL, pitch := PITCH, rate := RATE) -> void:
	log.append(text)
	if log.size() > 256:
		log.remove_at(0)
	if not Settings.announcer or Sfx.muted or not OS.has_feature("web"):
		return
	var vol := Settings.master_volume * Settings.sfx_volume
	if vol <= 0.01:
		return
	if not _installed:
		_installed = true
		JavaScriptBridge.eval(_JS, true)
	JavaScriptBridge.eval("window.__flSay&&window.__flSay(%s,%d,%s,%s,%s)" \
			% [JSON.stringify(text), prio, pitch, rate, minf(vol * 1.2, 1.0)], true)


## How many times `text` was requested since the log was last cleared (tests).
static func count(text: String) -> int:
	return log.count(text)
