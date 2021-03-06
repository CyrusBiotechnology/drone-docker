local windows_pipe = '\\\\\\\\.\\\\pipe\\\\docker_engine';
local windows_pipe_volume = 'docker_pipe';
local test_pipeline_name = 'testing';

local windows(os) = os == 'windows';

local golang_image(os, version) =
  'golang:' + '1.11' + if windows(os) then '-windowsservercore-' + version else '';

{
  test(os='linux', arch='amd64', version='')::
    local is_windows = windows(os);
    local golang = golang_image(os, version);
    local volumes = if is_windows then [{name: 'gopath', path: 'C:\\\\gopath'}] else [{name: 'gopath', path: '/go',}];
    {
      kind: 'pipeline',
      type: 'kubernetes',
      name: test_pipeline_name,
      steps: [
        {
          name: 'vet',
          image: golang,
          pull: 'always',
          environment: {
            GO111MODULE: 'on',
          },
          commands: [
            'go vet ./...',
          ],
          volumes: volumes,
        },
        {
          name: 'test',
          image: golang,
          pull: 'always',
          environment: {
            GO111MODULE: 'on',
          },
          commands: [
            'go test -cover ./...',
          ],
          volumes: volumes,
        },
      ],
      trigger: {
        ref: [
          'refs/heads/master',
          'refs/tags/**',
          'refs/pull/**',
        ],
      },
      volumes: [{name: 'gopath', temp: {}}]
    },

  build(name, os='linux', arch='amd64', version='')::
    local is_windows = windows(os);
    local tag = if is_windows then os + '-' + version else os + '-' + arch;
    local file_suffix = std.strReplace(tag, '-', '.');
    local volumes = if is_windows then [{ name: windows_pipe_volume, path: windows_pipe }] else [];
    local golang = golang_image(os, version);
    local plugin_repo = 'gcr.io/cyrus-containers/drone-plugins/' + name;
    local extension = if is_windows then '.exe' else '';
    local depends_on = if name == 'docker' then [test_pipeline_name] else [tag + '-docker'];
    {
      kind: 'pipeline',
      type: 'kubernetes',
      name: tag + '-' + name,
      steps: [
        {
          name: 'build-push',
          image: golang,
          pull: 'always',
          environment: {
            CGO_ENABLED: '0',
            GO111MODULE: 'on',
          },
          commands: [
            'go build -v -ldflags "-X main.version=${DRONE_COMMIT_SHA:0:8}" -a -tags netgo -o release/' + os + '/' + arch + '/drone-' + name + extension + ' ./cmd/drone-' + name,
          ],
          when: {
            event: {
              exclude: ['tag'],
            },
          },
        },
        {
          name: 'build-tag',
          image: golang,
          pull: 'always',
          environment: {
            CGO_ENABLED: '0',
            GO111MODULE: 'on',
          },
          commands: [
            'go build -v -ldflags "-X main.version=${DRONE_TAG##v}" -a -tags netgo -o release/' + os + '/' + arch + '/drone-' + name + extension + ' ./cmd/drone-' + name,
          ],
          when: {
            event: ['tag'],
          },
        },
        if name == "docker" then {
          name: 'executable',
          image: golang,
          pull: 'always',
          commands: [
            './release/' + os + '/' + arch + '/drone-' + name + extension + ' --help',
          ],
        },
        {
          name: 'dryrun',
          image: 'plugins/docker:' + tag,
          pull: 'always',
          settings: {
            dry_run: true,
            tags: tag,
            registry: 'gcr.io',
            dockerfile: 'docker/'+ name +'/Dockerfile.' + file_suffix,
            daemon_off: if is_windows then 'true' else 'false',
            repo: plugin_repo,
            username: { from_secret: 'docker_username' },
            password: { from_secret: 'docker_password' },
          },
          volumes: if std.length(volumes) > 0 then volumes,
          when: {
            event: ['pull_request'],
          },
        },
        {
          name: 'publish',
          image: 'plugins/docker:' + tag,
          pull: 'always',
          privileged: true,
          settings: {
            auto_tag: true,
            auto_tag_suffix: tag,
            registry: "gcr.io",
            daemon_off: if is_windows then 'true' else 'false',
            dockerfile: 'docker/' + name + '/Dockerfile.' + file_suffix,
            repo: plugin_repo,
            username: "_json_key",
            password: { from_secret: 'dockerconfigjson' },
          },
          volumes: if std.length(volumes) > 0 then volumes,
          when: {
            event: {
              exclude: ['pull_request'],
            },
          },
        },
      ],
      trigger: {
        ref: [
          'refs/heads/master',
          'refs/tags/**',
          'refs/pull/**',
        ],
      },
      depends_on: depends_on,
      volumes: if is_windows then [{ name: windows_pipe_volume, host: { path: windows_pipe } }],
    },
}