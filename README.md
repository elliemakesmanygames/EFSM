# Ellie's Finite State Machine (EFSM)
[![Source on GitHub](https://img.shields.io/badge/Source-GitHub-6e40c9?style=for-the-badge&logo=github&logoColor=white)](https://github.com/blackingsplash/EFSM)

**EFSM** is an expiremental state machine model that, instead of utilizing lifecycle functions, utilizes a single callback as a state. This callback is thus ran when transition() function is called in an asynchronous thread. To avoid
race condition, a CancellationToken design is implemented to regulate asynchrounous functions and soft kill. Although unfinished, it can still operate basic tasks such as initiating, transitioning state-to-state and
updating data. However, this model is restrictive when it comes to death states, and is somewhat a less flexible design as it requires more user input than usual.

# License
<p align="center">
  EFSM is released under the <a href="LICENSE.md">MIT License</a>.
</p>
