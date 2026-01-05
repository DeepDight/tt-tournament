export const dynamic = "force-dynamic";
import PlayerProfile from "@/component/PlayerProfile";
import { Metadata } from "next";

import createDeps from "@/service/create-deps";
import { notFound } from "next/navigation";

const { userService } = createDeps();

export const generateStaticParams = async (): Promise<{ id: string }[]> => {
  return [
    {
      id: "1",
    },

    {
      id: "28",
    },
    {
      id: "35",
    },
    {
      id: "13",
    },
    {
      id: "6",
    },

    {
      id: "4",
    },
    {
      id: "11",
    },
    {
      id: "2",
    },
    {
      id: "8",
    },

    {
      id: "9",
    },
    {
      id: "20",
    },
    {
      id: "18",
    },
    {
      id: "26",
    },
  ];
};

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const playerId = parseInt(id, 10);
  const playerData = await userService.getUserProfile(playerId);

  if (!playerData) {
    return {
      title: "Игрок не найден",
    };
  }

  return {
    title: `${playerData.player.name} — Теннис. Евроберег`,
  };
}

export default async function PlayerPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const playerId = parseInt(id, 10);
  const playerData = await userService.getUserProfile(playerId);

  if (!playerData) {
    notFound();
  }

  return (
    <PlayerProfile
      player={playerData.player}
      matchDetails={playerData.matchDetails}
    />
  );
}

export const fetchCache = "force-no-store";
