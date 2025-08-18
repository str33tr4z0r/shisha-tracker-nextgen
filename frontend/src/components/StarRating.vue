<template>
  <div class="inline-flex items-center" role="radiogroup" aria-label="Sternebewertung">
    <button
      v-for="s in 5"
      :key="s"
      type="button"
      class="relative p-1 focus:outline-none"
      :aria-checked="(displayValue >= s) ? 'true' : ((displayValue >= s - 0.5) ? 'mixed' : 'false')"
      @click="onClick($event, s)"
      @keydown.enter.prevent="onClick($event, s)"
    >
      <span
        class="block text-2xl leading-none star"
        :style="starStyle(s)"
        aria-hidden="true"
      >★</span>
    </button>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  modelValue?: number
  readonly?: boolean
  size?: string
}>()

const emit = defineEmits<{
  (e: 'update:modelValue', value: number): void
  (e: 'rate', value: number): void
}>()

const displayValue = computed(() => {
  const v = props.modelValue ?? 0
  // clamp between 0 and 5
  return Math.max(0, Math.min(5, v))
})

function starStyle(index: number) {
  // compute fill percentage for this star (0..100)
  const fill = Math.max(0, Math.min(1, (displayValue.value - (index - 1))))
  const pct = Math.round(fill * 100)
  // use CSS variables for colors so dark mode is consistent
  const filled = 'var(--star-color, #f59e0b)'
  const unfilled = 'var(--star-unfilled, #e5e7eb)'
  return {
    background: `linear-gradient(90deg, ${filled} ${pct}%, ${unfilled} ${pct}%)`,
    WebkitBackgroundClip: 'text',
    backgroundClip: 'text',
    color: filled,
    fontSize: props.size ?? '1.25rem',
  }
}

function onClick(e: MouseEvent | KeyboardEvent, starIndex: number) {
  if (props.readonly) return
  // If triggered by keyboard (Enter), treat as full-star selection.
  // If mouse event, detect half-star by pointer position.
  let isHalf = false
  try {
    // some events (KeyboardEvent) don't have clientX; guard access
    const me = e as MouseEvent
    if (typeof me.clientX === 'number') {
      const target = e.currentTarget as HTMLElement
      const rect = target.getBoundingClientRect()
      const x = me.clientX - rect.left
      isHalf = x < rect.width / 2
    }
  } catch (_) {
    isHalf = false
  }
  const value = (starIndex - 1) + (isHalf ? 0.5 : 1)
  emit('update:modelValue', value)
  emit('rate', value)
}
</script>

<style scoped>
/* ensure gradient clip works and unfilled fallback visible */
.star {
  -webkit-text-fill-color: transparent;
  -webkit-background-clip: text;
  background-clip: text;
}
</style>