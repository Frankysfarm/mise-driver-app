import { classifyUploadResponse, enqueue, legacyQueueMayBeDeleted, lifecycleExpectation, requiresSessionRotation, shouldTrack, type NativeLocationEvent } from '../../native/location-contract';
const equal = (actual: unknown, expected: unknown) => {
  if (actual !== expected) throw new Error(`expected ${String(expected)}, received ${String(actual)}`);
};
const base: NativeLocationEvent = { action_id:'a',installation_id:'i',session_id:'s',sequence:0,captured_at:'2026-07-27T00:00:00Z',
 latitude:0,longitude:0,accuracy_m:5,speed_mps:null,heading_deg:null,altitude_m:null,app_version:'1',app_build:'1',
 platform:'ios',app_state:'foreground',permission_state:'always',network_state:'online',
 tracking_mode:'continuous',battery_state:{level:.5,charging:false,low_power_mode:false},capability_flags:{} };
equal(shouldTrack('offline',true),false);
equal(shouldTrack('delivering',false),false);
equal(shouldTrack('delivering',true),true);
let queue: NativeLocationEvent[]=[];
for(let i=0;i<110;i++) queue=enqueue(queue,{...base,action_id:String(i),sequence:i});
equal(queue.length,100); equal(queue[0].sequence,10);
equal(lifecycleExpectation('ios','force_quit'),'cannot_guarantee_relaunch');
equal(lifecycleExpectation('android','force_quit'),'force_stop_requires_user_launch');
equal(lifecycleExpectation('ios','locked'),'background_updates_when_permission_and_policy_allow');
const cross = enqueue([
  {...base,action_id:'old',session_id:'z',sequence:2,captured_at:'2026-07-27T00:00:02Z'},
], {...base,action_id:'new',session_id:'a',sequence:1,captured_at:'2026-07-27T00:00:03Z'});
equal(cross[0].action_id,'old');
equal(requiresSessionRotation({state:'available',version:1},{state:'assigned',version:2}),true);
equal(requiresSessionRotation({state:'assigned',version:2},{state:'assigned',version:2}),false);
equal(shouldTrack('available',true),true); // shift start
equal(shouldTrack('offline',true),false); // shift end
equal(lifecycleExpectation('android','restart'),'os_controlled_resume_then_ordered_replay');
equal(classifyUploadResponse(409),'quarantine_dequeue_reauthorize');
equal(classifyUploadResponse(503),'retain_retry_bounded');
let staleThenLater=enqueue([],base);
staleThenLater=enqueue(staleThenLater,{...base,action_id:'later',sequence:1,captured_at:'2026-07-27T00:00:01Z'});
if(classifyUploadResponse(409)==='quarantine_dequeue_reauthorize') staleThenLater=staleThenLater.slice(1);
equal(staleThenLater[0].action_id,'later');
equal(classifyUploadResponse(200),'dequeue_success');
equal(legacyQueueMayBeDeleted([base],[{...base}]),true);
equal(legacyQueueMayBeDeleted([base],[{...base,latitude:1}]),false); // same count, altered payload
console.log('native location contract: PASS');
