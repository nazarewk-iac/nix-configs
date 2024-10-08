import configparser
import dataclasses
import functools
import json
import logging
from pathlib import Path

import fire

logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.DEBUG)


def iter_files(profile: Path):
    file = profile / "containers.json"
    confd = profile / "containers.json.d"

    if file.exists():
        yield file, json.loads(file.read_bytes())
    for p in confd.glob("*.json"):
        yield p, json.loads(p.read_bytes())


@dataclasses.dataclass
class Profile:
    config_profiles_path: Path
    config_section: str
    name: str
    path_string: str
    is_relative: bool
    is_default: bool

    @functools.cached_property
    def path(self):
        if self.is_relative:
            return self.config_profiles_path.parent / self.path_string
        return Path(self.path_string)


@dataclasses.dataclass()
class Program:
    config_path: str = str(Path.home() / ".mozilla/firefox")

    @functools.cached_property
    def _profiles(self):
        profiles_path = Path(self.config_path) / "profiles.ini"
        config = configparser.ConfigParser()
        config.read(profiles_path)
        assert config["General"]["Version"] == "2"

        profiles: dict[str, Profile] = {}
        for section_name in config.sections():
            if not section_name.startswith("Profile"):
                continue
            section = config[section_name]
            profile = Profile(
                config_profiles_path=profiles_path,
                config_section=section_name,
                name=section["Name"],
                path_string=section["Path"],
                is_default=section["Default"] == "1",
                is_relative=section["IsRelative"] == "1",
            )
            profiles[profile.name] = profile
        return profiles

    def profiles_list(self):
        for profile in self._profiles.values():
            yield profile.name

    def containers_config_render(self):
        for profile in self._profiles.values():
            profile_path = profile.path
            logging.info(f"Processing {profile_path}")
            output = profile_path / "containers.json"

            identities = {}
            last_context_id: int = -1
            for path, entry in iter_files(profile_path):
                logging.info(f"Reading {path}")
                context_id = entry.get("lastUserContextId", -1)
                if context_id > last_context_id:
                    if last_context_id >= 0:
                        logging.info(f'{profile_path}["lastUserContextId"] = {last_context_id=} -> {context_id=}')
                    last_context_id = context_id

                for identity in entry.get("identities", []):
                    iid = identity["userContextId"]
                    if identity.get("public") and iid > last_context_id:
                        logging.info(f'{profile_path}["lastUserContextId"] = {iid=}')
                        last_context_id = iid
                    existed = iid in identities
                    old = identities.setdefault(iid, {})
                    for key, new_value in identity.items():
                        old_value = old.get(key)
                        if old_value == new_value:
                            continue
                        if existed:
                            logging.info(f"{profile_path}[{iid=}][{key=}]: "
                                         f"{old_value=} -> {new_value=}")
                        old[key] = new_value

            if identities:
                output.write_text(json.dumps({
                    "version": 5,
                    "lastUserContextId": last_context_id,
                    "identities": sorted(
                        identities.values(),
                        key=lambda ident: ident["userContextId"]
                    ),
                }))


def main():
    fire.Fire(Program)


if __name__ == "__main__":
    main()
