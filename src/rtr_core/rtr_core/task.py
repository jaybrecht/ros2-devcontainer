from abc import ABC

from typing import cast

from dataclasses import dataclass

from rclpy.node import Node
from rclpy.lifecycle import LifecycleNode, LifecycleState, TransitionCallbackReturn
from rclpy.action import ActionServer
from rclpy.action.server import ServerGoalHandle

from rtr_interfaces.action import TaskAttempt
from rtr_interfaces.msg import Metric as MetricMsg
from rtr_interfaces.msg import Constraint as ConstraintMsg


@dataclass
class StateVar:
    pass


class Observation:
    pass


class Metric():
    def __init__(self, msg: MetricMsg):
        pass

    def __call__(self, _: Observation) -> bool: ...


class TaskMeasures(ABC):
    def __call__(self, _: StateVar) -> Observation: ...


class Constraint(Metric):
    def __init__(self, msg: ConstraintMsg):
        self._active_stages = msg.active_stages
        super().__init__(msg.evaluation_function)
        


class Evaluator:
    def __init__(self, metrics: list[Metric], constraints: list[Constraint], measures: TaskMeasures):
        self._metrics = metrics
        self._constraints = constraints
        self._measures = measures

    def evaluate(self, state: StateVar):
        observation = self._measures(state)

        for metric in self._metrics:
            metric(observation)



class TaskExecutor(LifecycleNode):
    def __init__(self, task_name: str):
        self._task_name = task_name
        super().__init__(f'{self._task_name}_executor')
        self._active = False

        self._measures = TaskMeasures()
        self._state = StateVar()

    @property
    def measures(self) -> TaskMeasures:
        return self._measures

    @property
    def state(self) -> StateVar:
        return self._state

    def on_configure(self, _: LifecycleState) -> TransitionCallbackReturn:
        self.timer_ = self.create_timer(0.1, self.update)
        return TransitionCallbackReturn.SUCCESS

    def on_activate(self, state: LifecycleState) -> TransitionCallbackReturn:
        self._active = True
        return super().on_activate(state)

    def on_deactivate(self, state: LifecycleState) -> TransitionCallbackReturn:
        self._active = False
        return super().on_deactivate(state)

    def update(self):
        if not self._active:
            return

        # Do work


class AtomicTask(Node):
    def __init__(self, task_name: str, task_executor: TaskExecutor):
        self._task_name = task_name

        super().__init__(f'{self._task_name}_action_server')

        self._task = task_executor

        self._action_server = ActionServer(
            node=self,
            action_type=TaskAttempt,
            action_name=f'{self._task_name}_attempt',
            goal_callback=self._goal_callback,
            handle_accepted_callback=self._handle_accepted_callback,
            execute_callback=self._execute_callback,
        )

        self._eval_timer_ = self.create_timer(0.1, self._evaluate)
        self._active = False

        self._evaluator: Evaluator | None = None

    def _goal_callback(self, goal: TaskAttempt.Goal):
        metrics = [Metric(metric) for metric in goal.metrics]
        constraints = [Constraint(constraint) for constraint in goal.constraints]

        self._evaluator = Evaluator(metrics, constraints, self._task.measures)

    def _handle_accepted_callback(self, goal_handle: ServerGoalHandle):
        self._active = True
        self._task.trigger_activate()

    def _evaluate(self):
        if not self._active:
            return

        if self._evaluator is None:
            raise RuntimeError("No evaluator")

        self._evaluator.evaluate(self._task.state)


        

