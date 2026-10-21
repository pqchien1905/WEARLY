export const AI_QUEUE = 'wearly-try-on';
export const AI_JOB_OPTIONS = {
  // A provider may have charged before an uncertain response. Never regenerate.
  attempts: 1,
  removeOnComplete: { age: 86400 },
  removeOnFail: { age: 604800 },
};
