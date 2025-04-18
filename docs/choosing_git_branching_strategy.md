# Choosing a Git Branching Strategy
![Image of branching strategy](./images/image-243-2.png)

Initially, we considered GitFlow and GitLab Workflow for our project's branching strategy. GitHub Flow was dismissed due to its lack of a dedicated developer branch, which we needed to clearly separate testing and production environments.

We chose the GitLab Workflow because it provided essential structure without GitFlow's complexity, fitting our team's size and experience.

We enforced our strategy using branch protection, mandatory code reviews, and automated CI/CD pipelines.

However, merging `develop` into `main` only on Tuesdays contradicted DevOps principles. To uphold Continuous Integration (CI), we changed our approach: immediately after merging to `develop`, we now promptly merge into `main`. Additionally, our VM now pulls from `main` daily via Cron, enhancing automation.

**Advantages:**

- Clear and simple branch management.
- Improved code quality and frequent deployments aligning with CI principles.

**Disadvantages:**

- Minor delays occasionally due to waiting for reviews.


Overall, we're very satisfied with this streamlined and efficient strategy.
