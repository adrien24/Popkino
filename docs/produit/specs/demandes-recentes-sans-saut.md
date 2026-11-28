# Rangée « Demandes récentes » sans saut à l'affichage

Statut : validée           Priorité : Should
Dernière mise à jour : 2026-11-28

## Problème

Depuis la livraison de « Demandes récentes » (spec `demandes-recentes-overseerr`), quand on ouvre une bibliothèque
(Séries, Films, Animés), les rangées habituelles s'affichent tout de suite, puis environ 1 s plus tard la rangée
« Demandes récentes » s'insère sous « Continuer à regarder » : tout ce qui est en dessous saute vers le bas.

Mots de l'utilisateur : « est ce qu'on pourrait mettre en cache et également mettre un skeleton pour les demandes
recentes pour pas que ça clip au moment de l'affichage ? »

Réponses déjà données (2026-11-28) :
- des affiches grises réservent la place, mais seulement si la bibliothèque avait des demandes la dernière fois ;
- pas d'affichage des dernières demandes gardées en cache : seulement les affiches grises, puis les vraies affiches
  avec leurs badges à jour.

Upstream : aucune issue trouvée (recherches « skeleton », « layout shift »). Plezy affiche déjà des affiches grises
de chargement sur son écran d'accueil ; la fonction « Demandes récentes » étant propre à Popkino, ce besoin aussi.

## Objectif

À l'ouverture d'une bibliothèque qui avait des demandes récentes, la place de la rangée est réservée tout de suite par
des affiches grises : les rangées en dessous ne bougent plus quand les vraies affiches arrivent.

## Parcours utilisateur

1. L'utilisateur ouvre la bibliothèque « Séries », qui avait des demandes récentes la dernière fois. Les rangées
   s'affichent comme aujourd'hui ; sous « Continuer à regarder », la rangée « Demandes récentes » apparaît aussitôt,
   avec son titre et des affiches grises de chargement.
2. Environ 1 s plus tard, les affiches grises sont remplacées sur place par les vraies affiches et leurs badges. Rien
   ne bouge au-dessus ni en dessous.
3. S'il appuie sur Bas pendant le chargement, le focus arrive sur la première affiche grise, comme il arrivera ensuite
   sur la vraie rangée. Quand les vraies affiches arrivent, le focus reste à la même position (2e affiche grise →
   2e vraie affiche).
4. Après un redémarrage de l'app ou de la TV, c'est pareil : l'app se souvient du nombre de demandes de chaque
   bibliothèque.

## Critères d'acceptation

- CA1 : Étant donné une bibliothèque dont la rangée « Demandes récentes » était affichée la dernière fois qu'elle a été
  ouverte, y compris avant un redémarrage de l'app ou de la TV, quand l'utilisateur l'ouvre, alors le titre « Demandes récentes » et
  des affiches grises apparaissent à la place de la rangée en même temps que les autres rangées.
- CA2 : Les affiches grises ont la même taille que les vraies affiches de la rangée et le même aspect que les affiches
  de chargement de l'écran d'accueil. Leur nombre est celui des affiches de la dernière fois, sans dépasser ce qui
  tient à l'écran.
- CA3 : Étant donné des affiches grises affichées, quand la réponse d'Overseerr arrive avec des demandes, alors les
  vraies affiches les remplacent sur place : les rangées au-dessus et en dessous ne changent pas de position (vérifié
  par une capture avant et après, sur la Fire TV Stick).
- CA4 : Les affiches grises ne montrent ni titre, ni badge, ni ancienne demande (aucune donnée gardée en cache n'est
  affichée).
- CA5 : Étant donné des affiches grises affichées, quand Overseerr répond qu'il n'y a plus aucune demande du type de la
  bibliothèque, alors la rangée disparaît et les rangées en dessous remontent (saut accepté, cas rare).
- CA6 : Étant donné des affiches grises affichées, quand Overseerr ne répond pas, alors elles disparaissent au plus
  tard 10 secondes après l'ouverture de la bibliothèque, sans message d'erreur ; les autres rangées restent utilisables
  pendant tout ce temps.
- CA6b : Étant donné les affiches grises retirées après 10 secondes, quand Overseerr répond plus tard, alors la rangée
  n'est pas insérée pendant cette visite (pas de second saut) ; elle apparaît à la prochaine ouverture de la
  bibliothèque.
- CA7 : Étant donné une bibliothèque qui n'avait pas de demandes la dernière fois (ou jamais ouverte), alors aucune
  affiche grise n'apparaît : comportement actuel (la rangée peut s'insérer si une demande vient d'être faite).
- CA8 : Étant donné l'app non reliée à Overseerr, ou une bibliothèque de musique, photos ou autre, alors jamais
  d'affiches grises.
- CA9 : Étant donné une bibliothèque rouverte alors que ses demandes sont encore à jour (moins de 30 s), alors les
  vraies affiches s'affichent directement, sans passer par les affiches grises.
- CA10 : Les affiches grises reçoivent le focus : Bas depuis « Continuer à regarder » arrive sur la première affiche
  grise, Gauche / Droite s'y déplacent, Bas mène à la rangée suivante. La touche OK sur une affiche grise ne fait
  rien.
- CA10b : Étant donné le focus sur une affiche grise, quand les vraies affiches arrivent, alors le focus reste à la
  même position dans la rangée (sur la dernière vraie affiche s'il y en a moins). Quand la rangée disparaît (CA5,
  CA6), le focus passe sur la première affiche de la rangée suivante (ou, à défaut, de la rangée précédente).
- CA10c : Dans tous les cas, le focus reste visible et n'est jamais perdu, qu'il soit au-dessus, dans ou sous la
  rangée quand elle change.
- CA13 : L'app ne mémorise sur la TV que le nombre de demandes affichées par bibliothèque, jamais les titres. Une
  bibliothèque dont la rangée n'apparaît plus (aucune demande) est oubliée : à l'ouverture suivante, pas d'affiches
  grises. Ce souvenir est propre au compte Overseerr connecté : changer de compte l'efface (au pire, un saut à la
  première ouverture de chaque bibliothèque avec le nouveau compte).
- CA11 : Le démarrage de l'app n'est pas plus long qu'avant (même mesure que pour `demandes-recentes-overseerr`), et
  rien n'est demandé à Overseerr avant l'ouverture d'une bibliothèque.
- CA12 : Comportement identique avec Plex et Jellyfin, Overseerr et Jellyseerr (Jellyfin vérifié par les tests
  automatiques seulement).
- CA14 : La grande zone d'aperçu en haut de l'écran (image, titre, résumé) n'est jamais vide à cause des affiches
  grises : à l'ouverture, elle montre le premier vrai titre de l'onglet, comme aujourd'hui, même quand la rangée grise
  est la première rangée (bibliothèque sans « Continuer à regarder ») ; quand le focus est sur une affiche grise,
  elle garde le dernier vrai titre affiché. Elle passe au titre de la vraie affiche dès que celle-ci reçoit le focus.

Recette uniquement sur la Fire TV Stick (192.168.1.173), jamais sur la Freebox.

## Hors périmètre

- Afficher les dernières demandes connues (affiches, titres, badges) avant la réponse d'Overseerr : refusé par
  l'utilisateur (2026-11-28).
- Accélérer la réponse d'Overseerr elle-même.
- Le saut dans les cas rares acceptés : bibliothèque sans demandes la dernière fois qui en a maintenant (CA7), demandes
  qui ont toutes disparu ou Overseerr injoignable (CA5, CA6).
- Les autres rangées des bibliothèques et de l'accueil (comportement de Plezy inchangé).

## Contraintes

- TV : focus toujours visible, jamais bloqué ; Retour inchangé.
- Rien de lu ni demandé au démarrage de l'app sur la Fire TV : l'information mémorisée n'est lue qu'à
  l'ouverture d'une bibliothèque.
- Rien de nouveau n'est collecté ni envoyé (Google Play : sécurité des données inchangée). L'information
  mémorisée sur l'appareil se limite à « cette bibliothèque avait N demandes », jamais les titres (CA13).
- Fusions avec Plezy : le moins possible de modifications des écrans existants.
- Aucune différence entre la version GitHub et les futures versions store.

## Questions ouvertes

Aucune. Réponses de l'utilisateur (2026-11-28) : souvenir gardé après redémarrage (nombre de demandes par
bibliothèque seulement), focus possible sur les affiches grises, délai maximum de 10 secondes. Spec validée par
l'utilisateur le 2026-11-28.

Décisions du PO dans la logique de la spec validée (questions de l'architecte plateforme, 2026-11-28) : réponse
d'Overseerr après 10 s ignorée jusqu'à la prochaine ouverture (CA6b) ; souvenir propre au compte Overseerr, effacé au
changement de compte (CA13) ; affiches grises fixes, sans animation, comme celles de l'accueil (CA2).
Décisions du PO (questions des architectes, 2026-11-28) : la grande zone d'aperçu du haut ignore les affiches grises
et garde le dernier vrai titre (CA14 ; remplace une première décision « zone grise et vide », revue parce qu'elle
aurait laissé la zone vide à chaque ouverture d'une bibliothèque sans « Continuer à regarder ») ; affiches grises avec les deux traits gris sous le rectangle, comme celles de l'accueil (CA2), à
condition que la hauteur totale de la rangée reste celle de la vraie rangée (CA3 prime).
