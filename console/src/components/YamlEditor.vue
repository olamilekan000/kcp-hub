<script setup lang="ts">
// A YAML editor: line numbers, highlighting, and the parse error marked
// where it is rather than only described below. Read-only, it is how YAML
// is shown anywhere it cannot be edited, so both look the same.
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { parseDocument } from 'yaml'
import { EditorState } from '@codemirror/state'
import {
  EditorView,
  drawSelection,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
  lineNumbers,
} from '@codemirror/view'
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands'
import { HighlightStyle, bracketMatching, indentOnInput, syntaxHighlighting } from '@codemirror/language'
import { yaml } from '@codemirror/lang-yaml'
import { linter, lintGutter, type Diagnostic } from '@codemirror/lint'
import { tags } from '@lezer/highlight'

const props = defineProps<{ modelValue: string; readonly?: boolean }>()
const emit = defineEmits<{ 'update:modelValue': [value: string]; submit: [] }>()

const host = ref<HTMLElement>()
let view: EditorView | undefined

const colors = HighlightStyle.define([
  { tag: [tags.propertyName, tags.definition(tags.propertyName)], color: 'var(--color-accent-hover)' },
  { tag: [tags.string, tags.special(tags.string)], color: 'var(--color-success)' },
  { tag: [tags.number, tags.bool, tags.null, tags.keyword], color: 'var(--color-warning)' },
  { tag: [tags.comment, tags.lineComment], color: 'var(--color-faint)', fontStyle: 'italic' },
  { tag: [tags.punctuation, tags.separator, tags.squareBracket, tags.brace], color: 'var(--color-muted)' },
  { tag: [tags.meta, tags.labelName, tags.typeName], color: 'var(--color-danger)' },
])

const theme = EditorView.theme({
  '&': { fontSize: '11.5px', backgroundColor: 'var(--color-raised)', height: '100%' },
  '&.cm-focused': { outline: 'none' },
  '.cm-scroller': { fontFamily: "'IBM Plex Mono', ui-monospace, monospace", lineHeight: '1.65' },
  '.cm-content': { padding: '10px 0', caretColor: 'var(--color-accent)' },
  '.cm-line': { padding: '0 14px 0 6px' },
  '.cm-gutters': {
    backgroundColor: 'var(--color-surface)',
    color: 'var(--color-faint)',
    borderRight: '1px solid var(--color-edge)',
  },
  '.cm-lineNumbers .cm-gutterElement': { padding: '0 8px 0 12px', minWidth: '28px' },
  '.cm-activeLine': { backgroundColor: 'var(--color-accent-subtle)' },
  '.cm-activeLineGutter': { backgroundColor: 'var(--color-accent-subtle)', color: 'var(--color-accent)' },
  '.cm-cursor': { borderLeftColor: 'var(--color-accent)', borderLeftWidth: '2px' },
  '&.cm-focused .cm-selectionBackground, .cm-selectionBackground': { backgroundColor: 'rgba(107, 72, 232, 0.18)' },
  '.cm-matchingBracket': { backgroundColor: 'var(--color-accent-subtle)', outline: '1px solid var(--color-accent)' },
  '.cm-tooltip-lint': { fontFamily: 'inherit', fontSize: '11px' },
})

const yamlErrors = linter(
  (v): Diagnostic[] =>
    parseDocument(v.state.doc.toString()).errors.map((e) => ({
      from: Math.min(e.pos[0], v.state.doc.length),
      to: Math.min(Math.max(e.pos[1], e.pos[0] + 1), v.state.doc.length),
      severity: 'error',
      message: e.message.split('\n')[0],
    })),
  { delay: 300 },
)

const editing = () => [
  highlightActiveLineGutter(),
  highlightActiveLine(),
  history(),
  indentOnInput(),
  bracketMatching(),
  yamlErrors,
  lintGutter(),
  keymap.of([
    { key: 'Mod-Enter', run: () => (emit('submit'), true) },
    indentWithTab,
    ...defaultKeymap,
    ...historyKeymap,
  ]),
  EditorView.updateListener.of((u) => {
    if (u.docChanged) emit('update:modelValue', u.state.doc.toString())
  }),
]

onMounted(() => {
  view = new EditorView({
    parent: host.value!,
    state: EditorState.create({
      doc: props.modelValue,
      extensions: [
        lineNumbers(),
        drawSelection(),
        yaml(),
        syntaxHighlighting(colors),
        EditorState.tabSize.of(2),
        theme,
        ...(props.readonly ? [EditorState.readOnly.of(true), EditorView.editable.of(false)] : editing()),
      ],
    }),
  })
  if (!props.readonly) view.focus()
})

// Text replaced from outside, such as on switching from the form tab.
watch(
  () => props.modelValue,
  (text) => {
    if (view && text !== view.state.doc.toString()) {
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } })
    }
  },
)

onBeforeUnmount(() => view?.destroy())
</script>

<template>
  <div v-if="readonly" ref="host" class="max-h-[60vh] overflow-auto" />
  <div v-else ref="host" class="h-[24rem] resize-y overflow-hidden" />
</template>
