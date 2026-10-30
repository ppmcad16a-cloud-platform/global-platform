// Cloudflare Worker "mern-failover" (stopped-standby failover).
// Cloudflare's notification "GCP pool unhealthy" POSTs here. The Worker
// checks the shared secret and starts the GitHub Actions workflow
// failover-wake in platform-automation, which wakes Azure and AWS.
const WORKFLOW_URL =
  "https://api.github.com/repos/ppmcad16a-cloud-platform/platform-automation/actions/workflows/failover-wake.yml/dispatches";

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("mern-failover: POST only\n", { status: 405 });
    }
    // Cloudflare sends the webhook secret in this header.
    if (request.headers.get("cf-webhook-auth") !== env.WEBHOOK_SECRET) {
      return new Response("forbidden\n", { status: 403 });
    }
    const body = await request.text();
    // Cloudflare sends a test message when the destination is created: ignore it.
    if (!body.includes("Unhealthy")) {
      return new Response("ignored (not an Unhealthy event)\n");
    }
    const gh = await fetch(WORKFLOW_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "mern-failover-worker",
      },
      body: JSON.stringify({
        ref: "main",
        inputs: { reason: "Cloudflare: primary (GCP) pool unhealthy" },
      }),
    });
    return new Response(`failover-wake dispatched: GitHub answered ${gh.status}\n`, {
      status: gh.status === 204 ? 200 : 502,
    });
  },
};
