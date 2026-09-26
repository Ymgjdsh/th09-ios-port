// Diagnostic build only. Include inside Application.cpp's extern "C" block.
// Application.cpp must include tests/world-snapshot.hpp outside that block.
#if defined(TH09_IOS_SMOKE) && TH09_IOS_SMOKE
struct NativeSmokeReplay {
    i32 phase=0,frame=0,compared=0,mismatch_frame=-1,mismatch_field=-1;
    i32 expected=0,actual=0;u32 bytes=0;std::string error;
    std::vector<std::array<i32,48>> snapshots;
};
static NativeSmokeReplay native_smoke_replay;

const i32* th09_smoke_state(){
    static i32 v[14]{};std::fill(std::begin(v),std::end(v),0);
    if(!probe)return v;
    const auto& p=*probe;v[0]=p.frames;v[1]=p.in_title;v[2]=p.paused;
    if(p.session){v[3]=p.session->frames;v[4]=i32(p.session->phase);}
    if(p.world){const auto& w=*p.world;const auto& player=*w.battle->fields[0].player;
        v[5]=w.dialogue->id;v[6]=w.scene->phase;v[7]=player.control.player_state;
        v[8]=player.motion.health;v[9]=player.input.held;v[10]=player.input.fire_frames;
        v[11]=i32(player.control.charge*1000);v[12]=i32(player.control.available*1000);
        v[13]=w.rules.progress.active_frames;
    }return v;
}

u32 th09_smoke_validate_save(){
    if(!probe)return 0;
    std::vector<u8> bytes;PlayerRecords records;GameConfiguration configuration;
    if(!read_file("/save/score.dat",bytes)||bytes.empty()||!records.load(bytes.data(),u32(bytes.size())))return 0;
    if(!read_file("/save/th09.cfg",bytes)||bytes.size()!=204||!configuration.load(bytes.data(),u32(bytes.size())))return 0;
    return 1;
}

static i32 smoke_replay_fail(const std::string& message){native_smoke_replay.error=message;native_smoke_replay.phase=-1;return -1;}

// This starts a separate ordinary two-human match, without modifying health,
// charge, projectiles, protection, round outcomes, or simulation timing.
i32 th09_smoke_replay_begin(){
    native_smoke_replay={};auto& test=native_smoke_replay;
    if(!probe)return smoke_replay_fail("No application");
    auto& p=*probe;clear_inputs();p.presentation.renderer.flush();p.presentation.world=nullptr;
    p.world=nullptr;p.session.reset();p.in_title=false;p.paused=p.over=p.complete=false;
    p.state.random={0x7531,0,0};p.executor.invalid=false;p.error.clear();
    WorldConfiguration configuration;configuration.selection.mode=GameMode::versus;
    configuration.selection.characters[0]=0;configuration.selection.characters[1]=1;
    configuration.selection.difficulty=1;configuration.selection.unlocked=p.records.versus_unlocked;
    configuration.controllers[0]=configuration.controllers[1]=0;
    ReplayMetadata metadata;metadata.mode=2;metadata.difficulty=1;metadata.versus=0;
    metadata.health[0]=metadata.health[1]=10;
    p.session=std::make_unique<GameSession>(p.state,p.resources,p.executor,p.presentation,p,p.records);
    if(!p.session->begin(configuration,metadata,"26/09/26"))return smoke_replay_fail(p.session->error);
    p.world=p.session->world.get();p.presentation.world=p.world;test.snapshots.reserve(900);
    test.phase=1;return 1;
}

// Bounded batches keep UIKit responsive. The native display loop must be
// suspended while this method advances normal GameSession::update calls.
i32 th09_smoke_replay_step(u32 budget){
    auto& test=native_smoke_replay;if(test.phase!=1&&test.phase!=2)return test.phase;
    if(!probe||!probe->session)return smoke_replay_fail("Session disappeared");
    auto& p=*probe;budget=std::min(budget,8u);
    for(u32 n=0;n<budget;++n){
        if(test.phase==1){
            const u32 frame=u32(test.frame);
            const u16 left=u16((frame%180<110?1:frame%6<3?1:0)|(frame%480<240?64:128)|(frame%73<20?4:0));
            const u16 right=u16((frame%8<4?1:0)|(frame%400<200?128:64));
            if(!p.session->update(left,right,left|right))return smoke_replay_fail(p.session->error);
            p.world=p.session->world.get();p.presentation.world=p.world;
            if(p.session->phase!=SessionPhase::match)return smoke_replay_fail("Recording ended before 900 ordinary frames");
            std::array<i32,48> snapshot;std::copy_n(audit::snapshot(p.world,p.state),48,snapshot.begin());
            test.snapshots.push_back(snapshot);++test.frame;
            if(test.frame==900){
                auto replay=p.session->save_replay("IOSSMOKE");const auto bytes=replay.encode();
                if(bytes.empty())return smoke_replay_fail("Recording serialization: "+p.session->error);
                if(!p.write_file("/save/native-smoke.rpy",bytes.data(),u32(bytes.size())))return smoke_replay_fail("Diagnostic replay write failed");
                // Decode the actual serialized file, not the in-memory recorder.
                std::vector<u8> restored;ReplayFile decoded;
                if(!read_file("/save/native-smoke.rpy",restored)||!decoded.decode(restored.data(),u32(restored.size())))return smoke_replay_fail("Diagnostic replay read/decode failed");
                test.bytes=u32(restored.size());p.presentation.renderer.flush();p.presentation.world=nullptr;p.world=nullptr;
                if(!p.session->play(decoded,9,false))return smoke_replay_fail(p.session->error);
                p.world=p.session->world.get();p.presentation.world=p.world;test.phase=2;test.frame=0;
                break;
            }
        }else{
            if(!p.session->update(0,0,0))return smoke_replay_fail(p.session->error);
            p.world=p.session->world.get();p.presentation.world=p.world;
            if(!p.world)return smoke_replay_fail("Playback lost world");
            const auto* actual=audit::snapshot(p.world,p.state);const auto& expected=test.snapshots[u32(test.frame)];
            for(i32 field=0;field<48;++field){
                // The RNG call counter is bookkeeping. The replay flag is the
                // only normalized gameplay flag; every other semantic field,
                // including both humans' input and RNG seed, is compared.
                if(field==1)continue;
                const i32 a=field==2?actual[field]&~8:actual[field];
                const i32 e=field==2?expected[field]&~8:expected[field];
                if(a!=e){test.mismatch_frame=test.frame;test.mismatch_field=field;test.actual=a;test.expected=e;
                    return smoke_replay_fail("Recording/playback semantic snapshot mismatch");}
                ++test.compared;
            }
            if(++test.frame==i32(test.snapshots.size())){test.phase=3;p.draw();break;}
        }
    }
    // Sound generation remains part of simulation; drain it between batches.
    p.audio.update();p.audio.pump();return test.phase;
}

const i32* th09_smoke_replay_status(){
    static i32 v[8];const auto& t=native_smoke_replay;
    v[0]=t.phase;v[1]=t.frame;v[2]=t.compared;v[3]=i32(t.bytes);
    v[4]=t.mismatch_frame;v[5]=t.mismatch_field;v[6]=t.expected;v[7]=t.actual;return v;
}
const char* th09_smoke_replay_error(){return native_smoke_replay.error.c_str();}
#endif
