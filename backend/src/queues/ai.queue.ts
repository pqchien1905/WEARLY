export const AI_QUEUE = 'wearly-try-on';
export const AI_JOB_OPTIONS = {
  attempts: 3,
  backoff: { type: 'exponential', delay: 2000 },
  removeOnComplete: { age: 86400 },
  removeOnFail: { age: 604800 },
};
