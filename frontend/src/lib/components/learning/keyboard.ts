/** Leave native controls, held keys and text composition to the browser. */
export function acceptsSessionShortcut(event: KeyboardEvent, allowButtonTarget = false): boolean {
  if (
    event.defaultPrevented ||
    event.repeat ||
    event.isComposing ||
    event.keyCode === 229 ||
    event.altKey ||
    event.ctrlKey ||
    event.metaKey
  )
    return false;
  const target = event.target as Element | null;
  const selector = 'input, textarea, select, a, [contenteditable]:not([contenteditable="false"])';
  return !target?.closest?.(allowButtonTarget ? selector : `${selector}, button`);
}
