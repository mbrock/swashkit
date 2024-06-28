#ifndef MIC_H
#define MIC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MicCtx MicCtx;

typedef void (*MicFun) (MicCtx *context);

extern MicCtx *
mic_init (MicFun fun, void *arg);

extern void
mic_free (MicCtx *context);

extern int
mic_scan (MicCtx *context);

extern int
mic_play (MicCtx *context, int idx);

extern void
mic_dev (MicCtx *context, int idx, const char **name, uint32_t *is_default);

extern void
mic_buf (MicCtx *context, const uint8_t **ptr, int *len);

extern void *
mic_arg (MicCtx *context);

#ifdef __cplusplus
}
#endif

#endif // MIC_H
