"""Small reversible file transaction for the source-tree setup commands."""
import os
import tempfile
import datetime


def check_path(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError('A setup target is a symlink or non-file; preserve it and resolve manually')
    parent = path.parent
    while not parent.exists():
        parent = parent.parent
    if not parent.is_dir() or not os.access(parent, os.W_OK | os.X_OK):
        raise ValueError('A setup target directory is not writable')


def atomic_write(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.cellar-setup-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


class Transaction:
    def __init__(self, paths):
        self.before = {}
        self.created_dirs = set()
        for path in paths:
            check_path(path)
            self.before[path] = (path.read_bytes(), path.stat().st_mode & 0o777) if path.exists() else None
            parent = path.parent
            while not parent.exists():
                self.created_dirs.add(parent)
                parent = parent.parent

    def backup(self, path):
        if self.before[path] is not None:
            suffix = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
            backup = path.with_name(path.name + '.cellar-backup-' + suffix)
            atomic_write(backup, self.before[path][0], 0o600)

    def rollback(self):
        errors = []
        for path, old in reversed(list(self.before.items())):
            try:
                if old is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic_write(path, *old)
            except OSError:
                errors.append(str(path))
        for directory in sorted(self.created_dirs, key=lambda p: len(p.parts), reverse=True):
            try:
                directory.rmdir()
            except OSError:
                pass
        if errors:
            raise RuntimeError('Rollback incomplete; restore the .cellar-backup files for: ' + ', '.join(errors))
