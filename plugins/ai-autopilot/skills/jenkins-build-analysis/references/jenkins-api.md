# Jenkins REST API — the endpoints these scripts use

Base URL: `$env:JENKINS_BASE_URL`. Auth: HTTP Basic, `user:API-token` (the token **replaces** the password).

## Job and build URLs

A job path becomes a URL by wrapping every segment in `/job/`:

```
JENKINS_ROOT_JOB=SPLE ; target 'MyComponent/main'
  -> {base}/job/SPLE/job/MyComponent/job/main
```

A build URL is the job URL plus a selector:

```
{job}/lastBuild   lastCompletedBuild   lastFailedBuild
{job}/lastStableBuild   lastSuccessfulBuild   lastUnsuccessfulBuild
{job}/431
```

> **Gotcha.** URLs copied from the Jenkins UI for multibranch jobs contain view filters
> (`.../job/pnd/view/change-requests/job/PR-832/`). `/view/<name>` is not part of the REST path and is
> stripped before use.

## Build metadata

```
GET {build}/api/json
```

`result` (`SUCCESS` | `FAILURE` | `UNSTABLE` | `ABORTED`, absent while running), `timestamp` (epoch ms),
`duration` (ms), `fullDisplayName`, `url`, and `actions[].causes[].shortDescription` for who or what
triggered it.

## Listing

```
GET {folder}/api/json?tree=jobs[name,color,url]
GET {job}/api/json?tree=builds[number,result,timestamp,duration]{0,10}
```

`color` encodes the last build's status: `blue*` = success, `red*` = failure, `yellow*` = unstable,
`*_anime` = currently running, `disabled` / `notbuilt`.

## Pipeline stages

```
GET {build}/wfapi/describe
```

Returns `name`, `status`, and `stages[]` with `id`, `name`, `status`, `durationMillis` and
`_links.self.href` — an **absolute path** to that stage's own describe endpoint.

```
GET {base}{stage._links.self.href}      -> { stageFlowNodes: [ {id, name, status}, ... ] }
GET {build}/execution/node/{nodeId}/wfapi/log   -> { text: "<span>...</span>..." }
```

- The stage node itself has no log; its child flow nodes do. Concatenate them.
- The `text` of a node log is **HTML-annotated** — strip the tags and HTML-decode.
- `404` on any `/wfapi` path means the job is not a Pipeline (or the Pipeline Stage View plugin is absent).
  Fall back to `{build}/consoleText`, which is plain text.

## Test results

```
GET {build}/testReport/api/json
```

`failCount`, `skipCount`, `passCount`, and `suites[].cases[]` with `className`, `name`, `status`
(`PASSED` | `FAILED` | `SKIPPED` | `REGRESSION` | `FIXED`) and `errorDetails`.

`404` means there is no test report — normally because the build failed before the tests ran.

## Status codes

| Code | Meaning |
|---|---|
| 401 | wrong `JENKINS_USER`, or an expired/mistyped API token |
| 403 | the token is valid but lacks permission on that job |
| 404 | no such job or build — or an endpoint that legitimately doesn't exist for this job type (`/wfapi`, `/testReport`) |
