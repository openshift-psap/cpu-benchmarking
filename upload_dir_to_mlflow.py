#!/usr/bin/env python3
import argparse
from pathlib import Path
import mlflow


def parse_tags(tag_args):
    tags = {}
    for item in tag_args or []:
        if "=" not in item:
            raise ValueError(f"Invalid tag '{item}'. Use key=value format.")
        key, value = item.split("=", 1)
        tags[key.strip()] = value.strip()
    return tags


def main():
    parser = argparse.ArgumentParser(description="Upload a directory to MLflow as artifacts")

    parser.add_argument("--dir", required=True, help="Directory to upload")
    parser.add_argument("--experiment-name", required=True, help="MLflow experiment name")
    parser.add_argument("--run-name", default=None, help="Optional MLflow run name")
    parser.add_argument("--artifact-path", default=None, help="Path inside the MLflow run artifacts")
    parser.add_argument("--tracking-uri", default=None, help="Optional MLflow tracking URI")
    parser.add_argument("--tag", action="append", help="MLflow tag in key=value format. Can be repeated.")

    args = parser.parse_args()

    upload_dir = Path(args.dir).resolve()
    if not upload_dir.is_dir():
        raise ValueError(f"Not a directory: {upload_dir}")

    if args.tracking_uri:
        mlflow.set_tracking_uri(args.tracking_uri)

    mlflow.set_experiment(args.experiment_name)

    tags = parse_tags(args.tag)

    with mlflow.start_run(run_name=args.run_name) as run:
        if tags:
            mlflow.set_tags(tags)

        mlflow.log_artifacts(
            local_dir=str(upload_dir),
            artifact_path=args.artifact_path,
        )

        print("Uploaded successfully")
        print(f"Experiment: {args.experiment_name}")
        print(f"Run ID: {run.info.run_id}")
        print(f"Artifact path: {args.artifact_path or '/'}")


if __name__ == "__main__":
    main()
