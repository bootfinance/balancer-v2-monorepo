import Task from '../../src/task';
import { TaskRunOptions } from '../../src/types';
import { ComposableCustomPoolDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as ComposableCustomPoolDeployment;

  const args = [input.Vault, input.ProtocolFeePercentagesProvider];
  await task.deployAndVerify('ComposableCustomPoolFactory', args, from, force);
};
