"""Prepare isolated macOS Godot user data without changing the user's home."""

from pathlib import Path
import sys
import uuid


def isolated_project(repo: Path, profile: Path) -> Path:
    """Keep sources shared, but give each Mac run its own project and user data."""
    if sys.platform != 'darwin':
        return repo
    repo = repo.resolve()
    profile = profile.resolve()
    if (repo / 'override.cfg').exists():
        raise RuntimeError('Remove the local override.cfg before an isolated Mac run')
    project = profile / 'project'
    project.mkdir(parents=True)
    for source in repo.iterdir():
        if source.name == 'project.godot' or source.name.startswith('.') and source.name != '.gutconfig.json':
            continue
        (project / source.name).symlink_to(source, target_is_directory=source.is_dir())
    (project / 'project.godot').write_bytes((repo / 'project.godot').read_bytes())
    user_directory = 'Frogger Automation/' + uuid.uuid4().hex
    (project / 'override.cfg').write_text(
        '[application]\nconfig/use_custom_user_dir=true\n'
        f'config/custom_user_dir_name="{user_directory}"\n', encoding='utf-8')
    user_path = Path.home() / 'Library/Application Support' / user_directory
    (profile / 'user-data-path.txt').write_text(str(user_path) + '\n', encoding='utf-8')
    print('Isolated Mac user data: ' + str(user_path), file=sys.stderr, flush=True)
    return project


if __name__ == '__main__':
    try:
        print(isolated_project(Path(sys.argv[1]), Path(sys.argv[2])))
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(2)
