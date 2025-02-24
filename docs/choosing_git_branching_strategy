# Choosing a Git Branching Strategy

Initially looking at the [branching strategies in Git](https://www.geeksforgeeks.org/branching-strategies-in-git/), the branching strategies which best seem to fit our project are the **GitFlow Workflow** and the **GitLab Workflow**. The reason why I’m ruling out the **GitHub Flow** is that it is missing a Developer branch. Since our code is deployed in production, it feels crucial to be able to differentiate between a test environment and a production environment via the Dev and Main branch.

To narrow it down and make a choice between **GitFlow** and **GitLab**, I looked deeper into the details of these two strategies. In general, you could say that:

- **GitFlow** is quite complex, with branches for hot-fixes, release, develop, and feature branches.
- **GitLab Workflow** brings many of the same features to the table, but in a simpler manner than GitFlow while still being more complex than GitHub Flow.

Based on this, I conclude that the branching strategy that fits our project best is the **GitLab Workflow**. The reasons for this are:

- We all have some experience with Git, so using something more complex than GitHub Flow shouldn’t be an issue.
- Since our code is running in production, it’s crucial that our strategy supports a Main and a Developer branch.
- Our project isn’t that big (e.g., involving multiple teams or building a large software application), so GitFlow seems overly complex, and more conflicts could occur if we chose that strategy.
