export const TRACKABLE_STATES = new Set(['available','assigned','at_pickup','delivering','returning']);
export const QUEUE_LIMIT = 100;

export type NativeLocationEvent = {
  action_id:string; session_id:string; sequence:number; captured_at:string;
  latitude:number; longitude:number; accuracy_m:number;
  speed_mps:number|null; heading_deg:number|null; app_version:string;
  app_build:string|null; platform:'ios'|'android'; app_state:'foreground'|'background'|'locked';
  permission_state:string; network_state:string; capability_flags:Record<string,boolean>;
};

export function shouldTrack(state:string, policyEnabled:boolean) {
  return policyEnabled && TRACKABLE_STATES.has(state);
}

export function enqueue(queue:readonly NativeLocationEvent[], event:NativeLocationEvent) {
  return [...queue.filter(x => x.action_id!==event.action_id
    && !(x.session_id===event.session_id && x.sequence===event.sequence)), event]
    .sort((a,b)=>Date.parse(a.captured_at)-Date.parse(b.captured_at)
      || a.sequence-b.sequence || a.action_id.localeCompare(b.action_id))
    .slice(-QUEUE_LIMIT);
}

export function lifecycleExpectation(platform:'ios'|'android', event:'force_quit'|'restart'|'locked') {
  if (event==='locked') return 'background_updates_when_permission_and_policy_allow';
  if (platform==='ios' && event==='force_quit') return 'cannot_guarantee_relaunch';
  if (platform==='android' && event==='force_quit') return 'force_stop_requires_user_launch';
  return 'os_controlled_resume_then_ordered_replay';
}

export function classifyUploadResponse(status:number) {
  if(status>=200&&status<300) return 'dequeue_success';
  if(status===409||(status>=400&&status<500&&status!==429)) return 'quarantine_dequeue_reauthorize';
  return 'retain_retry_bounded';
}

export function requiresSessionRotation(before:{state:string;version:number}|null, after:{state:string;version:number}) {
  return !before || before.state!==after.state || before.version!==after.version;
}

function canonical(value:unknown):string {
  if(Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if(value&&typeof value==='object') return `{${Object.entries(value as Record<string,unknown>)
    .sort(([a],[b])=>a.localeCompare(b)).map(([key,item])=>`${JSON.stringify(key)}:${canonical(item)}`).join(',')}}`;
  return JSON.stringify(value);
}

export function legacyQueueMayBeDeleted(expected:readonly NativeLocationEvent[], decrypted:readonly NativeLocationEvent[]) {
  return canonical(expected.slice(-QUEUE_LIMIT))===canonical(decrypted);
}
