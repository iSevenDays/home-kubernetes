# Resolving the `litellm-helm` Migration Job Failure in Flux

This document details the investigation and resolution of a recurring Helm deployment failure related to a migration job in the `openhands` chart.

## 1. Initial Problem

The deployment of the `openhands` application via a Flux `HelmRelease` was consistently failing. The primary symptoms were:

-   The `HelmRelease` would enter a perpetual loop of `UpgradeFailed` followed by `RollbackFailed`.
-   The core error message in the logs for both the upgrade and rollback was `jobs.batch "openhands-litellm-migrations" not found`.

Initial analysis revealed that the `litellm-helm` sub-chart created a Kubernetes `Job` for database migrations. This job was configured with a `ttlSecondsAfterFinished` policy, which caused Kubernetes to automatically delete the job after it completed successfully. However, the job was not configured as a Helm hook, so Helm tracked it as a permanent resource. When the TTL controller deleted the job, Helm's subsequent check would fail because the resource was missing, triggering a rollback and the failure loop.

## 2. Investigation Journey & Failed Attempts

Our goal was to make the migration job's lifecycle compatible with Flux and Helm's declarative, GitOps-based approach. This led us down several paths.

### Attempt 1: Using Helm Hooks

Our first approach was to treat the migration job as a proper Helm hook.

-   **Action**: We modified the `helmrelease.yaml.j2` to pass Helm hook annotations (`helm.sh/hook` and `helm.sh/hook-delete-policy`) to the `litellm-helm` sub-chart's `migrationJob`.
-   **Result**: This led to a new error: `Job.batch "openhands-litellm-migrations" is invalid: spec.template: Invalid value: ... field is immutable`.
-   **Reason**: Helm was trying to *patch* the existing, completed hook job on every subsequent reconciliation. Since many fields in a `Job`'s pod template are immutable after creation, this operation is not allowed. A Helm hook job needs to be unique on each run.

### Attempt 2: Unique Job Names with `Release.Revision`

To solve the immutable field error, we tried to make the job name unique for each deployment.

-   **Action**: We appended the Helm variable `-{{ .Release.Revision }}` to the `fullnameOverride` values for the main chart and the `litellm-helm` sub-chart in `helmrelease.yaml.j2`.
-   **Result**: The deployment failed with a different error: `failed to create resource: ConfigMap "openhands-litellm-{{ .Release.Revision }}-config" is invalid: metadata.name: Invalid value`.
-   **Reason**: Flux does not template the values passed to a `HelmRelease` CRD. It passed the raw string `{{ .Release.Revision }}` as part of the name, which is not a valid character sequence for a Kubernetes resource name.

### Attempt 3: A Standalone Job with Incorrect Dependencies

Realizing we couldn't easily modify the sub-chart's behavior, we moved to creating our own job.

-   **Action**:
    1.  Disabled the `migrationJob` in the `litellm-helm` sub-chart.
    2.  Created a new, separate `migration-job.yaml.j2` file in the top-level `openhands` directory.
    3.  Added this new job to the main `kustomization.yaml.j2`.
-   **Result**: The migration job's pod failed with the error: `secret "openhands-postgresql" not found`.
-   **Reason**: We had inadvertently broken the dependency chain. The new job was now part of the parent Kustomization, which did not have an explicit dependency on the `openhands-postgresql` Kustomization. The job was starting before the database secret had been created.

## 3. The Final Solution

The "secret not found" error was the final clue. It revealed that the core issue was not just the job's configuration, but its position within the GitOps dependency tree.

The correct and final solution was to create a standalone job but place it correctly within the Flux Kustomization hierarchy.

1.  **Disable the Sub-Chart Job**: In `templates/config/kubernetes/apps/openhands/openhands/app/helmrelease.yaml.j2`, we confirmed the `litellm-helm` sub-chart's migration job was disabled to prevent any conflicts.
    ```yaml
    # ...
    litellm-helm:
      # ...
      migrationJob:
        enabled: false
    # ...
    ```

2.  **Create and Correctly Place the Migration Job**: We created a new job definition in a file named `migration-job.yaml.j2`, but critically, we placed it inside `templates/config/kubernetes/apps/openhands/openhands/app/`.

3.  **Leverage Existing Dependencies**: The `Kustomization` that manages the `.../openhands/app/` directory (defined in `ks.yaml.j2`) already contained the necessary `dependsOn` clause:
    ```yaml
    # templates/config/kubernetes/apps/openhands/openhands/ks.yaml.j2
    # ...
    spec:
      # ...
      dependsOn:
        - name: openhands-postgresql
        - name: openhands-secrets
    ```

By placing our new `migration-job.yaml.j2` inside this directory, it was automatically included in this `Kustomization`. This ensured that the migration job would only be created and run *after* the `openhands-postgresql` and `openhands-secrets` Kustomizations were successfully reconciled and ready.

This approach solved the "secret not found" error and, because the job was managed independently by Flux outside of a Helm release, it completely bypassed the "immutable field" and "job not found" errors.

The deployment is now stable and successful.
