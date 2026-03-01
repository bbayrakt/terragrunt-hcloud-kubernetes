# NOTE
[MinIO repository is no longer maintained](https://news.ycombinator.com/item?id=47000041)

While there are some forks of MinIO now available, such as the [Chainguard Fork](https://github.com/chainguard-forks/minio), I have decided to move to another alternative.

# Instructions
After setting your values in `.env` and deploying the Docker compose file with `docker compose up -d`, you can either

- Set up your bucket using the web interface, hosted on port 9001, or
- Set up your bucket using [the MinIO Client](https://github.com/minio/mc)

And adjust your Terraform backend configuration.
