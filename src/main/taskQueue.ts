/** Serializes read-modify-write tasks while allowing failures to remain local. */
export class TaskQueue {
  private tail: Promise<unknown> = Promise.resolve();

  run<T>(task: () => Promise<T>): Promise<T> {
    const result = this.tail.catch(() => undefined).then(task);
    this.tail = result.catch(() => undefined);

    return result;
  }
}
