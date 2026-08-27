/** Blur commits controlled editors before a close snapshot unmounts them. */
export function commitActiveInput(documentRoot: Document): void {
  const active = documentRoot.activeElement;
  const elementType = documentRoot.defaultView?.HTMLElement;
  if (!elementType || !(active instanceof elementType)) return;

  active.blur();
}
